import Foundation
import AVFoundation
import Speech
import ShazamKit

/// Commands recognised after the "Hey Island" wake phrase (Section 8.3).
enum VoiceCommand: Equatable {
    case skip
    case previous
    case pause
    case play
    case replay
    case whoSingsThis
    case showLyrics
    case startRoom
    case volumeUp
    case volumeDown

    /// Matches a lowercased command phrase (the text following "hey
    /// island") against known keyword sets. Order matters: phrases that are
    /// substrings of other phrases (e.g. "play" inside "replay") are checked
    /// first. Returns `nil` if nothing recognisable was said.
    static func match(in text: String) -> VoiceCommand? {
        if text.contains("who sings this") || text.contains("who is this")
            || text.contains("what song is this") || text.contains("what is this song") {
            return .whoSingsThis
        }
        if text.contains("show lyrics") || text.contains("lyrics") {
            return .showLyrics
        }
        if text.contains("start") && text.contains("room") {
            return .startRoom
        }
        if text.contains("volume up") || text.contains("louder") || text.contains("turn it up") {
            return .volumeUp
        }
        if text.contains("volume down") || text.contains("quieter")
            || text.contains("lower") || text.contains("turn it down") {
            return .volumeDown
        }
        if text.contains("replay") || text.contains("again") || text.contains("repeat") {
            return .replay
        }
        if text.contains("skip") || text.contains("next") {
            return .skip
        }
        if text.contains("previous") || text.contains("go back") || text.contains("back") {
            return .previous
        }
        if text.contains("pause") || text.contains("stop") {
            return .pause
        }
        if text.contains("play") || text.contains("resume") || text.contains("continue") {
            return .play
        }
        return nil
    }
}

/// Always-listening, on-device voice control (FEATURE 5 / Section 8).
///
/// Runs a continuous `SFSpeechRecognizer` task over the microphone input,
/// watching for the wake phrase "Hey Island". Once heard, the remainder of
/// the utterance is matched against `VoiceCommand` and dispatched via
/// `onCommand`. "Who sings this?" is handled specially: it triggers a
/// `ShazamKit` match against the live microphone audio (`identifyCurrentAudio`).
///
/// Both speech recognition and Shazam matching use their own `AVAudioEngine`
/// instances with input taps, separate from `MoodEngine`'s tap -- each
/// engine instance binds its own audio unit to the default input device.
@MainActor
final class VoiceEngine: NSObject, ObservableObject {
    /// Fired when the wake phrase is heard / the listening window closes.
    var onListeningChanged: ((Bool) -> Void)?
    /// Fired with the command text spoken after the wake phrase.
    var onTranscript: ((String) -> Void)?
    /// Fired with a "Title — Artist" string, "No match found", or `nil` to clear.
    var onShazamResult: ((String?) -> Void)?
    /// Fired when a recognised command should be executed.
    var onCommand: ((VoiceCommand) -> Void)?

    private static let wakePhrase = "hey island"

    // MARK: Speech recognition

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let speechEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isSpeechTapInstalled = false
    private var listeningResetTask: Task<Void, Never>?

    // MARK: Shazam

    private let shazamEngine = AVAudioEngine()
    private var shazamSession: SHSession?
    private var isIdentifying = false
    private var identifyTimeoutTask: Task<Void, Never>?

    func start(appState: AppState) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else { return }
                Task { @MainActor in
                    self?.startListening()
                }
            }
        }
    }

    // MARK: - Wake word + command recognition

    private func startListening() {
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }
        guard !speechEngine.isRunning else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = speechEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        isSpeechTapInstalled = true

        do {
            speechEngine.prepare()
            try speechEngine.start()
        } catch {
            print("[VoiceEngine] failed to start speech engine: \(error)")
            teardownSpeechTap()
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.handleTranscript(result.bestTranscription.formattedString)
                }
                if error != nil || result?.isFinal == true {
                    self.restartListening()
                }
            }
        }
    }

    private func restartListening() {
        teardownSpeechTap()
        recognitionTask?.cancel()
        recognitionTask = nil
        startListening()
    }

    private func teardownSpeechTap() {
        guard isSpeechTapInstalled else { return }
        speechEngine.inputNode.removeTap(onBus: 0)
        speechEngine.stop()
        isSpeechTapInstalled = false
    }

    private func handleTranscript(_ transcript: String) {
        let lowered = transcript.lowercased()
        guard let range = lowered.range(of: Self.wakePhrase) else { return }

        onListeningChanged?(true)
        scheduleListeningReset()

        let commandText = String(lowered[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        onTranscript?(commandText)

        guard !commandText.isEmpty, let command = VoiceCommand.match(in: commandText) else { return }

        onCommand?(command)
        onListeningChanged?(false)
        listeningResetTask?.cancel()
        restartListening()
    }

    private func scheduleListeningReset() {
        listeningResetTask?.cancel()
        listeningResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.onListeningChanged?(false)
        }
    }

    // MARK: - ShazamKit ("Who sings this?")

    /// Captures ~12 seconds of microphone audio and matches it against
    /// Shazam's catalogue (Section 8.4). Reports the result via
    /// `onShazamResult`.
    func identifyCurrentAudio() {
        guard !isIdentifying else { return }
        isIdentifying = true
        onShazamResult?("Listening\u{2026}")

        let session = SHSession()
        session.delegate = self
        shazamSession = session

        let input = shazamEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            finishIdentify(result: "Microphone unavailable")
            return
        }

        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak session] buffer, time in
            session?.matchStreamingBuffer(buffer, at: time)
        }

        do {
            shazamEngine.prepare()
            try shazamEngine.start()
        } catch {
            finishIdentify(result: "Microphone unavailable")
            return
        }

        identifyTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finishIdentify(result: "No match found")
        }
    }

    private func finishIdentify(result: String?) {
        guard isIdentifying else { return }
        isIdentifying = false
        identifyTimeoutTask?.cancel()
        identifyTimeoutTask = nil
        shazamEngine.inputNode.removeTap(onBus: 0)
        shazamEngine.stop()
        shazamSession = nil
        onShazamResult?(result)
    }
}

extension VoiceEngine: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        let item = match.mediaItems.first
        let title = item?.title ?? "Unknown title"
        let artist = item?.artist ?? "Unknown artist"
        Task { @MainActor in
            self.finishIdentify(result: "\(title) \u{2014} \(artist)")
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        Task { @MainActor in
            self.finishIdentify(result: "No match found")
        }
    }
}
