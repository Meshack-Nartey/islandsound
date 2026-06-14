import Foundation
import Network
import CryptoKit

/// Message shape posted by the Boomplay/YouTube Music browser extension
/// content scripts (Section 5.4):
/// `{ title, artist, position, source: "boomplay" | "youtube" }`
struct BrowserBridgeMessage: Codable {
    var title: String?
    var artist: String?
    var position: Double?
    var source: String
}

/// Minimal local WebSocket server (RFC 6455) listening on
/// `ws://localhost:47832/browser-bridge`, used by FEATURE 2's companion
/// browser extension to report what's playing on Boomplay / YouTube Music.
///
/// Implemented directly on top of `Network` + `CryptoKit` (both first-party
/// Apple frameworks) rather than a third-party WebSocket library, per
/// Section 11.1 ("never import any third-party Swift packages").
final class BrowserBridgeServer {
    fileprivate static let handshakeGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: BridgeConnection] = [:]
    private let queue = DispatchQueue(label: "com.aethelis.islandsound.browserbridge")

    /// Called (on `queue`) for every decoded JSON message from any browser tab.
    var onMessage: ((BrowserBridgeMessage) -> Void)?

    init(port: UInt16 = 47832) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: port) else {
            print("[BrowserBridgeServer] failed to bind port \(port.rawValue)")
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[BrowserBridgeServer] listener failed: \(error)")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.close() }
        connections.removeAll()
    }

    /// Pushes a `PLAY_REQUEST` command to every connected browser tab, used
    /// by `PlaybackEngine.handoff(to:)` when handing off to Boomplay or
    /// YouTube Music. Returns `true` if at least one tab was connected to
    /// receive it (handoff to a browser source with no extension connected
    /// is reported as "Track not available").
    @discardableResult
    func requestPlay(title: String, artist: String, position: Double, source: String) -> Bool {
        let payload: [String: Any] = [
            "type": "PLAY_REQUEST",
            "title": title,
            "artist": artist,
            "position": position,
            "source": source
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }

        return queue.sync {
            guard !connections.isEmpty else { return false }
            for connection in connections.values {
                connection.sendText(data)
            }
            return true
        }
    }

    private func accept(_ nwConnection: NWConnection) {
        let connection = BridgeConnection(connection: nwConnection, queue: queue)
        connection.onMessage = { [weak self] message in
            self?.onMessage?(message)
        }
        connection.onClose = { [weak self] in
            self?.connections.removeValue(forKey: ObjectIdentifier(nwConnection))
        }
        connections[ObjectIdentifier(nwConnection)] = connection
        connection.start()
    }
}

/// A single browser-tab WebSocket connection: performs the HTTP -> WebSocket
/// upgrade handshake, then frames/deframes RFC 6455 messages.
private final class BridgeConnection {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private var didHandshake = false

    var onMessage: ((BrowserBridgeMessage) -> Void)?
    var onClose: (() -> Void)?

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveLoop()
            case .failed, .cancelled:
                self?.onClose?()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func close() {
        connection.cancel()
    }

    /// Sends a JSON payload to this tab as a WebSocket text frame.
    func sendText(_ data: Data) {
        send(opcode: Opcode.text, payload: data)
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.process()
            }

            if isComplete || error != nil {
                self.onClose?()
                return
            }

            self.receiveLoop()
        }
    }

    private func process() {
        if !didHandshake {
            performHandshakeIfPossible()
        }
        if didHandshake {
            processFrames()
        }
    }

    // MARK: - HTTP Upgrade Handshake

    private func performHandshakeIfPossible() {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }

        let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
        buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)

        guard
            let headerString = String(data: headerData, encoding: .utf8),
            let key = Self.extractHeader(named: "Sec-WebSocket-Key", from: headerString)
        else {
            close()
            return
        }

        let accept = Self.acceptValue(for: key)
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r

        """

        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.didHandshake = true
                self?.process()
            } else {
                self?.close()
            }
        })
    }

    private static func extractHeader(named name: String, from headers: String) -> String? {
        for line in headers.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func acceptValue(for key: String) -> String {
        let magic = key + BrowserBridgeServer.handshakeGUID
        let digest = Insecure.SHA1.hash(data: Data(magic.utf8))
        return Data(digest).base64EncodedString()
    }

    // MARK: - WebSocket Framing (RFC 6455)

    private struct Frame {
        let opcode: UInt8
        let payload: Data
    }

    /// Opcode constants.
    private enum Opcode {
        static let text: UInt8 = 0x1
        static let close: UInt8 = 0x8
        static let ping: UInt8 = 0x9
        static let pong: UInt8 = 0xA
    }

    private func processFrames() {
        while let frame = Self.parseFrame(from: &buffer) {
            switch frame.opcode {
            case Opcode.text:
                if let message = try? JSONDecoder().decode(BrowserBridgeMessage.self, from: frame.payload) {
                    onMessage?(message)
                }
            case Opcode.ping:
                send(opcode: Opcode.pong, payload: frame.payload)
            case Opcode.close:
                send(opcode: Opcode.close, payload: Data())
                close()
            default:
                break
            }
        }
    }

    /// Attempts to parse one complete frame from `buffer`, removing its
    /// bytes on success. Returns `nil` if the buffer doesn't yet contain a
    /// full frame (caller should wait for more data).
    private static func parseFrame(from buffer: inout Data) -> Frame? {
        guard buffer.count >= 2 else { return nil }

        let bytes = [UInt8](buffer)
        let opcode = bytes[0] & 0x0F
        let masked = (bytes[1] & 0x80) != 0
        var payloadLength = Int(bytes[1] & 0x7F)
        var offset = 2

        if payloadLength == 126 {
            guard bytes.count >= offset + 2 else { return nil }
            payloadLength = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
        } else if payloadLength == 127 {
            guard bytes.count >= offset + 8 else { return nil }
            var length = 0
            for i in 0..<8 { length = (length << 8) | Int(bytes[offset + i]) }
            payloadLength = length
            offset += 8
        }

        var maskKey: [UInt8] = []
        if masked {
            guard bytes.count >= offset + 4 else { return nil }
            maskKey = Array(bytes[offset..<offset + 4])
            offset += 4
        }

        guard bytes.count >= offset + payloadLength else { return nil }

        var payload = Data(bytes[offset..<offset + payloadLength])
        if masked {
            for i in 0..<payload.count {
                payload[payload.startIndex + i] ^= maskKey[i % 4]
            }
        }

        buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + offset + payloadLength))
        return Frame(opcode: opcode, payload: payload)
    }

    private func send(opcode: UInt8, payload: Data) {
        var frame = Data()
        frame.append(0x80 | opcode) // FIN + opcode, server frames are unmasked

        if payload.count <= 125 {
            frame.append(UInt8(payload.count))
        } else if payload.count <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((payload.count >> shift) & 0xFF))
            }
        }

        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }
}
