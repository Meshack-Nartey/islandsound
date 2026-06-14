import XCTest
@testable import IslandSound

/// `AudioAnalyzer` is pure computation (FFT over sample buffers), so it's
/// directly testable with synthetic signals -- no `AVAudioEngine` tap
/// required (Section 4.2-4.3 / 13).
final class AudioAnalyzerTests: XCTestCase {
    private let sampleRate = 44100.0
    private let fftSize = 2048
    private let hop = 1024

    /// Number of samples needed to produce `frames` spectra (50% overlap).
    private func sampleCount(forFrames frames: Int) -> Int {
        hop * (frames - 1) + fftSize
    }

    private func sineWave(frequency: Double, sampleCount: Int) -> [Float] {
        (0..<sampleCount).map { i in
            Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    func testAnalyzeReturnsNilWithFewerThanFourFrames() {
        let analyzer = AudioAnalyzer()
        analyzer.append(samples: sineWave(frequency: 440, sampleCount: sampleCount(forFrames: 3)), sampleRate: sampleRate)

        XCTAssertNil(analyzer.analyze())
    }

    func testSilenceProducesZeroEnergyAndWarmth() {
        let analyzer = AudioAnalyzer()
        let silence = [Float](repeating: 0, count: sampleCount(forFrames: 4))
        analyzer.append(samples: silence, sampleRate: sampleRate)

        let result = try! XCTUnwrap(analyzer.analyze())

        XCTAssertEqual(result.energy, 0)
        XCTAssertEqual(result.warmth, 0)
        XCTAssertEqual(result.bpm, 0)
    }

    func testLowFrequencyToneHasHigherWarmthThanEnergy() {
        let analyzer = AudioAnalyzer()
        // 100Hz sits well below the 250Hz low/high cutoff.
        let tone = sineWave(frequency: 100, sampleCount: sampleCount(forFrames: 6))
        analyzer.append(samples: tone, sampleRate: sampleRate)

        let result = try! XCTUnwrap(analyzer.analyze())

        XCTAssertGreaterThan(result.warmth, result.energy)
        XCTAssertGreaterThan(result.warmth, 0.5)
    }

    func testHighFrequencyToneHasHigherEnergyThanWarmth() {
        let analyzer = AudioAnalyzer()
        // 2kHz sits well above the 250Hz low/high cutoff.
        let tone = sineWave(frequency: 2000, sampleCount: sampleCount(forFrames: 6))
        analyzer.append(samples: tone, sampleRate: sampleRate)

        let result = try! XCTUnwrap(analyzer.analyze())

        XCTAssertGreaterThan(result.energy, result.warmth)
        XCTAssertLessThan(result.warmth, 0.5)
    }

    func testResultsAreClampedToZeroToOne() {
        let analyzer = AudioAnalyzer()
        let tone = sineWave(frequency: 2000, sampleCount: sampleCount(forFrames: 6))
        analyzer.append(samples: tone, sampleRate: sampleRate)

        let result = try! XCTUnwrap(analyzer.analyze())

        XCTAssertTrue((0...1).contains(result.energy))
        XCTAssertTrue((0...1).contains(result.warmth))
    }

    func testResetClearsAccumulatedSpectra() {
        let analyzer = AudioAnalyzer()
        analyzer.append(samples: sineWave(frequency: 440, sampleCount: sampleCount(forFrames: 4)), sampleRate: sampleRate)
        XCTAssertNotNil(analyzer.analyze())

        analyzer.reset()

        XCTAssertNil(analyzer.analyze())
    }
}
