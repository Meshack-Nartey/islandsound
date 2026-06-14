import Foundation
import AVFoundation

/// Real-time BPM + spectral analysis -> island glow colour/animation output
/// (FEATURE 1 — Mood-Based Dynamic Theming).
///
/// Captures audio via an `AVAudioEngine` input tap (Section 4.2/4.3),
/// forwards sample buffers to `AudioAnalyzer` for FFT-based BPM/energy/
/// warmth estimation, and maps the result to a `MoodTheme` at most once
/// every 2 seconds (Section 4 PERFORMANCE rule).
///
/// The audio tap is only installed while `isPlaying == true`; on pause it's
/// torn down immediately so the app uses ~0% CPU at idle (Section 11.3).
@MainActor
final class MoodEngine: ObservableObject {
    /// Fired whenever the mood theme changes by more than the throttle
    /// threshold in `MoodTheme.shouldUpdate`.
    var onThemeChanged: ((MoodTheme) -> Void)?

    private let engine = AVAudioEngine()
    private let analyzer = AudioAnalyzer()

    private var isTapInstalled = false
    private var isPlaying = false
    private var currentTheme: MoodTheme = .neutral
    private var lastAnalysisDate = Date.distantPast

    func start(appState: AppState) {
        // The audio tap starts lazily on first `setPlaying(true)` -- see
        // class doc. Nothing to do at launch.
    }

    /// Called by `AppState` whenever `PlaybackEngine` reports a play/pause
    /// transition.
    func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing

        if isPlaying {
            startTap()
        } else {
            stopTap()
            publish(.neutral)
        }
    }

    // MARK: - Audio Tap

    private func startTap() {
        guard !isTapInstalled else { return }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            // No input device available (e.g. headless CI) -- stay neutral.
            return
        }

        let sampleRate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

            Task { @MainActor in
                self?.consume(samples: samples, sampleRate: sampleRate)
            }
        }

        do {
            try engine.start()
            isTapInstalled = true
        } catch {
            print("[MoodEngine] failed to start audio engine: \(error)")
            input.removeTap(onBus: 0)
        }
    }

    private func stopTap() {
        guard isTapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isTapInstalled = false
        analyzer.reset()
    }

    // MARK: - Analysis

    private func consume(samples: [Float], sampleRate: Double) {
        analyzer.append(samples: samples, sampleRate: sampleRate)

        let now = Date()
        guard now.timeIntervalSince(lastAnalysisDate) >= 2.0 else { return }
        guard let result = analyzer.analyze() else { return }
        lastAnalysisDate = now

        let theme = MoodTheme.from(
            bpm: result.bpm,
            energy: result.energy,
            warmth: result.warmth,
            isPlaying: isPlaying
        )
        publish(theme)
    }

    private func publish(_ theme: MoodTheme) {
        guard currentTheme.shouldUpdate(to: theme) else { return }
        currentTheme = theme
        onThemeChanged?(theme)
    }
}
