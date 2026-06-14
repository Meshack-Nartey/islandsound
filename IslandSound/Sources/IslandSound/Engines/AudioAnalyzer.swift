import Foundation
import Accelerate

/// On-device BPM / energy / warmth analysis using Accelerate's vDSP FFT,
/// per FEATURE 1 (Section 4.2-4.3). Pure computation, no audio I/O, so it's
/// directly unit-testable independent of `MoodEngine`'s `AVAudioEngine` tap.
final class AudioAnalyzer {
    struct Result {
        let bpm: Double
        let energy: Double // 0...1, normalised mid/high-frequency energy
        let warmth: Double // 0...1, ratio of low-to-total frequency energy
    }

    private let fftSize = 2048
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let window: [Float]

    private var sampleBuffer: [Float] = []
    /// One magnitude spectrum per analysed frame, oldest first.
    private var spectra: [[Float]] = []
    private var sampleRate: Double = 44100

    /// Bounds memory & flux-calculation cost to roughly the last 2 seconds
    /// of audio at a 50% overlap hop size.
    private let maxSpectra = 80

    init() {
        let fftSize = self.fftSize
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = (0..<fftSize).map { i in
            0.5 - 0.5 * cos(2 * Float.pi * Float(i) / Float(fftSize - 1)) // Hann window
        }
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func reset() {
        sampleBuffer.removeAll()
        spectra.removeAll()
    }

    /// Feeds newly-captured samples in. Internally chunks them into
    /// `fftSize`-length, 50%-overlapping frames and computes a magnitude
    /// spectrum for each.
    func append(samples: [Float], sampleRate: Double) {
        self.sampleRate = sampleRate
        sampleBuffer.append(contentsOf: samples)

        let hop = fftSize / 2
        while sampleBuffer.count >= fftSize {
            let frame = Array(sampleBuffer[0..<fftSize])
            spectra.append(magnitudeSpectrum(of: frame))
            if spectra.count > maxSpectra {
                spectra.removeFirst(spectra.count - maxSpectra)
            }
            sampleBuffer.removeFirst(min(hop, sampleBuffer.count))
        }
    }

    /// Runs the full BPM/energy/warmth analysis over the accumulated
    /// spectra. Returns `nil` if there isn't enough data yet (e.g. just
    /// after playback started).
    func analyze() -> Result? {
        guard spectra.count >= 4 else { return nil }
        let bpm = estimateBPM()
        let (energy, warmth) = estimateEnergyAndWarmth()
        return Result(bpm: bpm, energy: energy, warmth: warmth)
    }

    // MARK: - FFT

    private func magnitudeSpectrum(of frame: [Float]) -> [Float] {
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                windowed.withUnsafeMutableBufferPointer { windowedPtr in
                    windowedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }

                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        return magnitudes
    }

    // MARK: - BPM (onset / spectral-flux detection, Section 4.3)

    /// 1. Spectral flux between consecutive frames (half-wave rectified)
    /// 2. Peak-pick the flux signal
    /// 3. Average inter-peak interval -> BPM, folded into 60-180 BPM range
    private func estimateBPM() -> Double {
        var flux: [Float] = []
        for i in 1..<spectra.count {
            let prev = spectra[i - 1]
            let curr = spectra[i]
            var sum: Float = 0
            for bin in 0..<curr.count {
                let diff = curr[bin] - prev[bin]
                if diff > 0 { sum += diff } // half-wave rectification
            }
            flux.append(sum)
        }
        guard !flux.isEmpty else { return 0 }

        let mean = flux.reduce(0, +) / Float(flux.count)
        let threshold = mean * 1.5

        var peakIndices: [Int] = []
        for i in 0..<flux.count where flux[i] > threshold {
            if let last = peakIndices.last, i - last < 2 { continue } // debounce
            peakIndices.append(i)
        }
        guard peakIndices.count >= 2 else { return 0 }

        let hopSeconds = Double(fftSize / 2) / sampleRate
        var intervals: [Double] = []
        for i in 1..<peakIndices.count {
            intervals.append(Double(peakIndices[i] - peakIndices[i - 1]) * hopSeconds)
        }
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        guard avgInterval > 0 else { return 0 }

        var bpm = 60.0 / avgInterval
        while bpm < 60 { bpm *= 2 }
        while bpm > 180 { bpm /= 2 }
        return bpm
    }

    // MARK: - Energy & Warmth

    /// `energy` = normalised mid/high-frequency magnitude (drives "how
    /// electric" the theme feels). `warmth` = proportion of total energy
    /// sitting below 250Hz (drives the worship/gospel amber-gold branch).
    private func estimateEnergyAndWarmth() -> (energy: Double, warmth: Double) {
        guard let latest = spectra.last, !latest.isEmpty else { return (0, 0) }

        let binHz = sampleRate / Double(fftSize)
        let lowCutoffBin = max(1, min(Int(250 / binHz), latest.count))

        let lowBins = latest[0..<lowCutoffBin]
        let highBins = latest[lowCutoffBin...]

        let lowEnergy = lowBins.reduce(0, +)
        let highEnergy = highBins.reduce(0, +)
        let total = lowEnergy + highEnergy

        guard total > 0 else { return (0, 0) }

        let energy = Double(highEnergy / Float(highBins.count))
        let warmth = Double(lowEnergy / total)

        // Soft-normalise energy into 0...1 (empirically tuned scale factor).
        return (min(energy / 8.0, 1), min(warmth, 1))
    }
}
