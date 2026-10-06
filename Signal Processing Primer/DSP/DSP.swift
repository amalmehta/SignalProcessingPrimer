import Accelerate
import Foundation

/// Pure, testable signal-processing routines used by every demo.
/// Everything works on plain `[Float]` buffers so it can be plotted, played or tested directly.
enum DSP {

    // MARK: - Generating signals

    enum Waveform: String, CaseIterable, Identifiable {
        case sine = "Sine", square = "Square", sawtooth = "Sawtooth", triangle = "Triangle"
        var id: String { rawValue }
    }

    /// One component of a mixed signal.
    struct Partial: Equatable {
        var frequency: Double
        var amplitude: Double
        var phase: Double = 0
    }

    static func tone(_ waveform: Waveform = .sine, frequency: Double, amplitude: Double = 1,
                     phase: Double = 0, sampleRate: Double, count: Int) -> [Float] {
        (0..<count).map { n in
            let cycles = frequency * Double(n) / sampleRate + phase / (2 * .pi)
            let p = cycles - floor(cycles)                      // position in cycle, 0..<1
            let v: Double
            switch waveform {
            case .sine:     v = sin(2 * .pi * p)
            case .square:   v = p < 0.5 ? 1 : -1
            case .sawtooth: v = 2 * p - 1
            case .triangle: v = p < 0.5 ? 4 * p - 1 : 3 - 4 * p
            }
            return Float(amplitude * v)
        }
    }

    static func mix(_ partials: [Partial], sampleRate: Double, count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        for p in partials where p.amplitude != 0 {
            let t = tone(frequency: p.frequency, amplitude: p.amplitude, phase: p.phase,
                         sampleRate: sampleRate, count: count)
            vDSP.add(out, t, result: &out)
        }
        return out
    }

    /// Linear sweep from `f0` to `f1` Hz.
    static func chirp(from f0: Double, to f1: Double, sampleRate: Double, count: Int) -> [Float] {
        let duration = Double(count) / sampleRate
        let k = (f1 - f0) / duration
        return (0..<count).map { n in
            let t = Double(n) / sampleRate
            return Float(sin(2 * .pi * (f0 * t + 0.5 * k * t * t)))
        }
    }

    /// Deterministic white noise in -1...1 (seeded so plots don't flicker between redraws).
    static func noise(count: Int, seed: UInt64 = 42) -> [Float] {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        return (0..<count).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: state >> 1) % 2_000_001) / 1_000_000 - 1
        }
    }

    static func normalized(_ x: [Float], peak: Float = 0.9) -> [Float] {
        let m = vDSP.maximumMagnitude(x)
        return m > 0 ? vDSP.multiply(peak / m, x) : x
    }

    // MARK: - Sampling & quantization

    /// The frequency you actually hear/see when `frequency` is sampled at `sampleRate`.
    static func aliasedFrequency(_ frequency: Double, sampleRate: Double) -> Double {
        let f = frequency.truncatingRemainder(dividingBy: sampleRate)
        return f > sampleRate / 2 ? sampleRate - f : f
    }

    /// Rounds every sample to one of 2^bits evenly spaced levels in -1...1.
    static func quantize(_ x: [Float], bits: Int, dither: Bool = false) -> [Float] {
        let levels = Float(1 << (bits - 1))
        let d = dither ? noise(count: x.count, seed: 7) : []
        return x.indices.map { i in
            let lsb = 1 / levels
            let v = x[i] + (dither ? d[i] * lsb : 0)
            return min(max((v * levels).rounded() / levels, -1), 1 - lsb)
        }
    }

    /// Signal-to-noise ratio in dB between a reference and a processed version.
    static func snr(reference: [Float], processed: [Float]) -> Double {
        let err = vDSP.subtract(reference, processed)
        let ps = Double(vDSP.sumOfSquares(reference)), pn = Double(vDSP.sumOfSquares(err))
        return pn == 0 ? .infinity : 10 * log10(ps / pn)
    }

    // MARK: - Windows

    enum Window: String, CaseIterable, Identifiable {
        case rectangular = "Rectangular", hann = "Hann", hamming = "Hamming", blackman = "Blackman"
        var id: String { rawValue }

        func coefficients(_ n: Int) -> [Float] {
            switch self {
            case .rectangular: return [Float](repeating: 1, count: n)
            case .hann:     return vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
            case .hamming:  return vDSP.window(ofType: Float.self, usingSequence: .hamming, count: n, isHalfWindow: false)
            case .blackman: return vDSP.window(ofType: Float.self, usingSequence: .blackman, count: n, isHalfWindow: false)
            }
        }
    }

    // MARK: - Fourier

    /// Single-sided magnitude spectrum (bins 0...n/2) of a power-of-two-length signal.
    /// Scaled so a full-scale sine of amplitude A shows a peak of ≈ A (rectangular window).
    static func magnitudeSpectrum(_ x: [Float], window: Window = .rectangular) -> [Float] {
        let n = x.count
        precondition(n > 0 && n & (n - 1) == 0, "FFT length must be a power of two")
        let w = window.coefficients(n)
        let real = vDSP.multiply(x, w)
        let dft = try! vDSP.DiscreteFourierTransform(previous: nil, count: n, direction: .forward,
                                                    transformType: .complexComplex, ofType: Float.self)
        let (re, im) = dft.transform(real: real, imaginary: [Float](repeating: 0, count: n))
        let gain = 2 / vDSP.sum(w)
        return (0...n / 2).map { (k: Int) -> Float in
            let power: Float = re[k] * re[k] + im[k] * im[k]
            return power.squareRoot() * gain * (k == 0 ? 0.5 : 1)
        }
    }

    static func decibels(_ mags: [Float], floor: Float = -100) -> [Float] {
        mags.map { max(20 * log10(max($0, 1e-12)), floor) }
    }

    /// Short-time Fourier transform: one magnitude-in-dB column per frame.
    /// Columns hold bins 0...frameSize/2. One FFT setup is reused for every frame.
    static func spectrogram(_ x: [Float], frameSize n: Int, hop: Int) -> [[Float]] {
        guard x.count >= n, n & (n - 1) == 0 else { return [] }
        let w = Window.hann.coefficients(n), gain = 2 / vDSP.sum(w)
        let zeros = [Float](repeating: 0, count: n)
        let dft = try! vDSP.DiscreteFourierTransform(previous: nil, count: n, direction: .forward,
                                                    transformType: .complexComplex, ofType: Float.self)
        return stride(from: 0, through: x.count - n, by: max(hop, 1)).map { start in
            let frame = vDSP.multiply(Array(x[start..<start + n]), w)
            let (re, im) = dft.transform(real: frame, imaginary: zeros)
            let mags = (0...n / 2).map { (k: Int) -> Float in
                let power: Float = re[k] * re[k] + im[k] * im[k]
                return power.squareRoot() * gain
            }
            return decibels(mags)
        }
    }

    /// Applies a sparse impulse response (a few non-zero taps) — the fast path for echoes.
    static func sparseConvolve(_ x: [Float], taps: [(delay: Int, gain: Float)]) -> [Float] {
        var y = [Float](repeating: 0, count: x.count)
        for tap in taps where tap.delay < x.count {
            for n in tap.delay..<x.count { y[n] += tap.gain * x[n - tap.delay] }
        }
        return y
    }

    // MARK: - Convolution & filtering

    /// Full linear convolution trimmed to the input length ("same" alignment, causal).
    static func convolve(_ x: [Float], kernel h: [Float]) -> [Float] {
        guard !h.isEmpty, !x.isEmpty else { return x }
        // Leading zeros make it causal; the overlay returns vector.count − kernel.count samples, hence one trailing zero.
        let padded = [Float](repeating: 0, count: h.count - 1) + x + [0]
        // vDSP.convolve walks the kernel backwards (true convolution), so pass h as-is.
        return vDSP.convolve(padded, withKernel: h)
    }

    static func movingAverageKernel(_ length: Int) -> [Float] {
        [Float](repeating: 1 / Float(length), count: max(length, 1))
    }

    static func gaussianKernel(_ length: Int) -> [Float] {
        let n = max(length, 1), sigma = max(Float(n) / 6, 0.5), mid = Float(n - 1) / 2
        let k = (0..<n).map { exp(-pow(Float($0) - mid, 2) / (2 * sigma * sigma)) }
        return vDSP.divide(k, vDSP.sum(k))
    }

    /// A single echo: the dry impulse plus a quieter copy `delay` samples later.
    static func echoKernel(delay: Int, gain: Float) -> [Float] {
        var k = [Float](repeating: 0, count: delay + 1)
        k[0] = 1; k[delay] = gain
        return k
    }

    /// Second-order IIR section, coefficients from the RBJ "Audio EQ Cookbook".
    struct Biquad: Equatable {
        enum Kind: String, CaseIterable, Identifiable {
            case lowPass = "Low-pass", highPass = "High-pass", bandPass = "Band-pass", peak = "Peak EQ", notch = "Notch"
            var id: String { rawValue }
        }
        var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

        init(_ kind: Kind, cutoff: Double, q: Double, gainDB: Double = 0, sampleRate: Double) {
            let w0 = 2 * .pi * cutoff / sampleRate, cw = cos(w0), alpha = sin(w0) / (2 * q)
            let A = pow(10, gainDB / 40)
            var b: (Double, Double, Double), a: (Double, Double, Double)
            switch kind {
            case .lowPass:  b = ((1 - cw) / 2, 1 - cw, (1 - cw) / 2); a = (1 + alpha, -2 * cw, 1 - alpha)
            case .highPass: b = ((1 + cw) / 2, -(1 + cw), (1 + cw) / 2); a = (1 + alpha, -2 * cw, 1 - alpha)
            case .bandPass: b = (alpha, 0, -alpha); a = (1 + alpha, -2 * cw, 1 - alpha)
            case .notch:    b = (1, -2 * cw, 1); a = (1 + alpha, -2 * cw, 1 - alpha)
            case .peak:     b = (1 + alpha * A, -2 * cw, 1 - alpha * A); a = (1 + alpha / A, -2 * cw, 1 - alpha / A)
            }
            b0 = b.0 / a.0; b1 = b.1 / a.0; b2 = b.2 / a.0; a1 = a.1 / a.0; a2 = a.2 / a.0
        }

        /// |H(e^jω)| in dB at `frequency` Hz.
        func responseDB(at frequency: Double, sampleRate: Double) -> Double {
            let w = 2 * .pi * frequency / sampleRate
            func evalPoly(_ c0: Double, _ c1: Double, _ c2: Double) -> (Double, Double) {
                (c0 + c1 * cos(-w) + c2 * cos(-2 * w), c1 * sin(-w) + c2 * sin(-2 * w))
            }
            let (nr, ni) = evalPoly(b0, b1, b2), (dr, di) = evalPoly(1, a1, a2)
            return 10 * log10(max((nr * nr + ni * ni) / (dr * dr + di * di), 1e-20))
        }

        func process(_ x: [Float]) -> [Float] {
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            return x.map { s in
                let xn = Double(s)
                let y = b0 * xn + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = xn; y2 = y1; y1 = y
                return Float(y)
            }
        }
    }

    // MARK: - Dynamics

    struct Compressor {
        var thresholdDB: Double, ratio: Double, attackMs: Double, releaseMs: Double, makeupDB: Double = 0

        /// Static curve: output level for a given input level (both dBFS).
        func outputLevel(forInput db: Double) -> Double {
            (db <= thresholdDB ? db : thresholdDB + (db - thresholdDB) / ratio) + makeupDB
        }

        /// Returns the processed signal and the gain reduction (dB, ≤ 0) applied at each sample.
        func process(_ x: [Float], sampleRate: Double) -> (output: [Float], gainDB: [Float]) {
            let att = exp(-1 / (attackMs * 0.001 * sampleRate)), rel = exp(-1 / (releaseMs * 0.001 * sampleRate))
            var env = 0.0
            var out = [Float](repeating: 0, count: x.count), gains = out
            for i in x.indices {
                let level = abs(Double(x[i]))
                env = level > env ? att * env + (1 - att) * level : rel * env + (1 - rel) * level
                let inDB = 20 * log10(max(env, 1e-6))
                let reduction = min(0, outputLevel(forInput: inDB) - makeupDB - inDB)
                gains[i] = Float(reduction)
                out[i] = x[i] * Float(pow(10, (reduction + makeupDB) / 20))
            }
            return (out, gains)
        }
    }

    /// Synthetic drum loop: alternating loud kicks and quiet ghost hits.
    static func drumLoop(sampleRate: Double, seconds: Double) -> [Float] {
        let count = Int(sampleRate * seconds)
        var out = [Float](repeating: 0, count: count)
        let hitEvery = Int(sampleRate * 0.25)
        let noiseBed = noise(count: count, seed: 3)
        for (i, start) in stride(from: 0, to: count, by: hitEvery).enumerated() {
            let loud: Float = [1.0, 0.18, 0.55, 0.12][i % 4]
            let length = min(Int(sampleRate * 0.2), count - start)
            for n in 0..<length {
                let t = Double(n) / sampleRate
                let body = Float(sin(2 * .pi * (55 + 90 * exp(-t * 30)) * t)) * Float(exp(-t * 18))
                out[start + n] += loud * (0.8 * body + 0.2 * noiseBed[start + n] * Float(exp(-t * 60)))
            }
        }
        return out
    }

    /// Envelope (peak per block) for plotting long signals compactly.
    static func envelope(_ x: [Float], blocks: Int) -> [Float] {
        guard !x.isEmpty, blocks > 0 else { return [] }
        let size = max(x.count / blocks, 1)
        return stride(from: 0, to: x.count, by: size).map { s in
            vDSP.maximumMagnitude(Array(x[s..<min(s + size, x.count)]))
        }
    }

    /// Picks ~`target` evenly spaced points so charts stay fast.
    static func decimateForPlot(_ x: [Float], target: Int = 600) -> [(Int, Float)] {
        let step = max(x.count / target, 1)
        return stride(from: 0, to: x.count, by: step).map { ($0, x[$0]) }
    }
}
