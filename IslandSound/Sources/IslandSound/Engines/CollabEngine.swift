import Foundation

/// Client for the `islandsound-server` collaborative listening rooms backend
/// (FEATURE 3 / Section 6). Speaks STOMP-over-WebSocket directly on top of
/// `URLSessionWebSocketTask` -- no third-party STOMP/SockJS library, per
/// Section 11.1.
///
/// Protocol contract with the server:
/// - `POST {serverBaseURL}/api/rooms` -> `{ "code": "ABC123" }` (host only)
/// - WebSocket STOMP endpoint at `{webSocketURL}`
/// - `SUBSCRIBE /topic/room/{code}` -- broadcast channel for `SyncMessage`,
///   `ReactionMessage`, `ParticipantUpdate` (discriminated by their `type` field)
/// - `SEND /app/room/{code}/join` -- announce this participant
/// - `SEND /app/room/{code}/sync` -- host broadcasts playback state every 3s
/// - `SEND /app/room/{code}/reaction` -- guest sends an emoji reaction
@MainActor
final class CollabEngine: ObservableObject {
    /// Fired whenever the local session state changes (join/leave, roster,
    /// reactions, last sync). `nil` means "not in a room".
    var onSessionChanged: ((CollabSession?) -> Void)?

    /// Fired when a `SYNC` message arrives for a session where the local
    /// role is `.guest` -- the host's own broadcasts are not echoed back.
    var onRemoteSync: ((SyncMessage) -> Void)?

    /// Override via `ISLANDSOUND_SERVER_URL` environment variable for local
    /// development against a non-default port.
    private static var serverBaseURL: String {
        ProcessInfo.processInfo.environment["ISLANDSOUND_SERVER_URL"] ?? "http://localhost:8080"
    }

    private static var webSocketURL: String {
        serverBaseURL.replacingOccurrences(of: "http", with: "ws") + "/ws"
    }

    private static let subscriptionId = "sub-room"
    private static let avatars = ["🙂", "🎧", "🎶", "🔥", "🌴", "✨", "🎤", "🪩"]

    private weak var appState: AppState?
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: CollabSession?
    private var syncBroadcastTask: Task<Void, Never>?

    private var isStompConnected = false
    private var pendingFrames: [String] = []

    private lazy var localParticipant = Participant(
        name: ProcessInfo.processInfo.environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? "Listener",
        avatar: Self.avatars.randomElement() ?? "🙂"
    )

    func start(appState: AppState) {
        self.appState = appState
        // WebSocket connection happens lazily on createRoom()/joinRoom(code:).
    }

    // MARK: - Public API

    /// Creates a new room via the REST API, then connects as `.host`.
    func createRoom() async {
        guard let code = await requestNewRoomCode() else {
            print("[CollabEngine] failed to create room -- is islandsound-server running?")
            return
        }
        connect(code: code, role: .host)
    }

    /// Joins an existing room by its code, connecting as `.guest`.
    func joinRoom(code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        connect(code: trimmed, role: .guest)
    }

    /// Leaves the current room and tears down the WebSocket connection.
    func leaveRoom() async {
        guard let session else { return }
        sendStompFrame(command: "SEND", headers: ["destination": "/app/room/\(session.code)/leave"], body: encode(localParticipant))
        sendStompFrame(command: "DISCONNECT", headers: [:])

        syncBroadcastTask?.cancel()
        syncBroadcastTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isStompConnected = false
        pendingFrames.removeAll()

        self.session = nil
        onSessionChanged?(nil)
    }

    /// Sends an emoji reaction to everyone else in the room (Section 6.3).
    func sendReaction(_ emoji: String) {
        guard let session else { return }
        let message = ReactionMessage(emoji: emoji, from: localParticipant.name)
        sendStompFrame(command: "SEND", headers: ["destination": "/app/room/\(session.code)/reaction"], body: encode(message))

        // Reflect locally immediately for the sender's own UI.
        var updated = session
        updated.recentReactions.append(message)
        if updated.recentReactions.count > 5 {
            updated.recentReactions.removeFirst(updated.recentReactions.count - 5)
        }
        self.session = updated
        onSessionChanged?(updated)
    }

    // MARK: - Room creation (REST)

    private struct RoomResponse: Decodable {
        let code: String
    }

    private func requestNewRoomCode() async -> String? {
        guard let url = URL(string: "\(Self.serverBaseURL)/api/rooms") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try JSONDecoder().decode(RoomResponse.self, from: data).code
        } catch {
            return nil
        }
    }

    // MARK: - WebSocket / STOMP

    private func connect(code: String, role: CollabRole) {
        guard let url = URL(string: Self.webSocketURL) else { return }

        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        isStompConnected = false
        pendingFrames.removeAll()
        task.resume()

        let newSession = CollabSession(code: code, role: role, participants: [localParticipant], isConnected: false)
        session = newSession
        onSessionChanged?(newSession)

        receiveLoop()

        sendStompFrame(command: "CONNECT", headers: ["accept-version": "1.2", "host": "localhost"])
        sendStompFrame(command: "SUBSCRIBE", headers: ["id": Self.subscriptionId, "destination": "/topic/room/\(code)"])
        sendStompFrame(command: "SEND", headers: ["destination": "/app/room/\(code)/join"], body: encode(localParticipant))

        if role == .host {
            startSyncBroadcast(code: code)
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleStompFrames(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleStompFrames(text)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveLoop()
                case .failure(let error):
                    print("[CollabEngine] websocket error: \(error)")
                    self.handleDisconnect()
                }
            }
        }
    }

    private func handleDisconnect() {
        syncBroadcastTask?.cancel()
        syncBroadcastTask = nil
        isStompConnected = false
        guard var session else { return }
        session.isConnected = false
        self.session = session
        onSessionChanged?(session)
    }

    // MARK: - STOMP framing

    /// STOMP frames are `COMMAND\nheader:value\n...\n\nbody\0`. Multiple
    /// frames may arrive concatenated in a single WebSocket message.
    private func buildFrame(command: String, headers: [String: String], body: String) -> String {
        var frame = command + "\n"
        for (key, value) in headers {
            frame += "\(key):\(value)\n"
        }
        frame += "\n" + body + "\u{0}"
        return frame
    }

    /// CONNECT is sent immediately; everything else is queued until the
    /// server's CONNECTED frame arrives, since STOMP requires the handshake
    /// to complete before SUBSCRIBE/SEND.
    private func sendStompFrame(command: String, headers: [String: String], body: String = "") {
        let frame = buildFrame(command: command, headers: headers, body: body)
        if command == "CONNECT" || isStompConnected {
            webSocketTask?.send(.string(frame)) { error in
                if let error { print("[CollabEngine] send error: \(error)") }
            }
        } else {
            pendingFrames.append(frame)
        }
    }

    private func flushPendingFrames() {
        guard isStompConnected else { return }
        let frames = pendingFrames
        pendingFrames.removeAll()
        for frame in frames {
            webSocketTask?.send(.string(frame)) { error in
                if let error { print("[CollabEngine] send error: \(error)") }
            }
        }
    }

    private func handleStompFrames(_ text: String) {
        for rawFrame in text.split(separator: "\u{0}", omittingEmptySubsequences: true) {
            parseFrame(String(rawFrame))
        }
    }

    private func parseFrame(_ frame: String) {
        let lines = frame.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let command = lines.first, !command.isEmpty else { return }

        var index = 1
        while index < lines.count, !lines[index].isEmpty {
            index += 1
        }
        let body = lines[min(index + 1, lines.count)...].joined(separator: "\n")

        switch command {
        case "CONNECTED":
            isStompConnected = true
            if var session {
                session.isConnected = true
                self.session = session
                onSessionChanged?(session)
            }
            flushPendingFrames()
        case "MESSAGE":
            handleIncomingPayload(body)
        case "ERROR":
            print("[CollabEngine] STOMP error: \(body)")
        default:
            break
        }
    }

    // MARK: - Incoming payloads

    private struct TypeEnvelope: Decodable {
        let type: String
    }

    private func handleIncomingPayload(_ body: String) {
        guard let data = body.data(using: .utf8) else { return }
        guard let envelope = try? JSONDecoder().decode(TypeEnvelope.self, from: data) else { return }
        guard var session else { return }

        switch envelope.type {
        case "SYNC":
            guard let sync = try? JSONDecoder().decode(SyncMessage.self, from: data) else { return }
            session.lastSync = sync
            self.session = session
            onSessionChanged?(session)
            if session.role == .guest {
                onRemoteSync?(sync)
            }

        case "REACTION":
            guard let reaction = try? JSONDecoder().decode(ReactionMessage.self, from: data) else { return }
            session.recentReactions.append(reaction)
            if session.recentReactions.count > 5 {
                session.recentReactions.removeFirst(session.recentReactions.count - 5)
            }
            self.session = session
            onSessionChanged?(session)

        case "PARTICIPANT_UPDATE":
            guard let update = try? JSONDecoder().decode(ParticipantUpdate.self, from: data) else { return }
            session.participants = update.participants
            self.session = session
            onSessionChanged?(session)

        default:
            break
        }
    }

    // MARK: - Host sync broadcast (Section 6.4)

    private func startSyncBroadcast(code: String) {
        syncBroadcastTask?.cancel()
        syncBroadcastTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.broadcastSync(code: code)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func broadcastSync(code: String) {
        guard let appState, let track = appState.currentTrack else { return }
        let sync = SyncMessage(
            trackId: track.id,
            trackTitle: track.title,
            artist: track.artist,
            position: appState.playbackPosition,
            isPlaying: appState.isPlaying,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
        sendStompFrame(command: "SEND", headers: ["destination": "/app/room/\(code)/sync"], body: encode(sync))
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
