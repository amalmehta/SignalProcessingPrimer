import SwiftUI

/// Test material for the audio-filtering demos.
enum AudioSource: String, CaseIterable, Identifiable {
    case noisyTone = "Noisy tone", whiteNoise = "White noise", sawtooth = "Sawtooth bass", drums = "Drum loop"
    var id: String { rawValue }

    func samples(count: Int) -> [Float] {
        let fs = DemoAudio.fs
        switch self {
        case .noisyTone:  return zip(DSP.tone(frequency: 220, amplitude: 0.5, sampleRate: fs, count: count),
                                     DSP.noise(count: count)).map { $0 + 0.25 * $1 }
        case .whiteNoise: return DSP.noise(count: count).map { $0 * 0.4 }
        case .sawtooth:   return DSP.tone(.sawtooth, frequency: 110, amplitude: 0.4, sampleRate: fs, count: count)
        case .drums:      return DSP.drumLoop(sampleRate: fs, seconds: Double(count) / fs).map { $0 * 0.8 }
        }
    }
}

// MARK: - Lesson 7: Convolution

struct ConvolutionDemo: View {
    enum KernelKind: String, CaseIterable, Identifiable {
        case movingAverage = "Moving average", gaussian = "Gaussian", echo = "Echo", multiEcho = "Repeating echo"
        var id: String { rawValue }
        var isEcho: Bool { self == .echo || self == .multiEcho }
    }
    @State private var kind = KernelKind.movingAverage
    @State private var length = 21.0
    @State private var delayMs = 180.0
    @State private var feedback = 0.5
    @State private var source = AudioSource.noisyTone

    private var taps: [(delay: Int, gain: Float)] {
        let d = Int(delayMs / 1000 * DemoAudio.fs)
        switch kind {
        case .echo:      return [(0, 1), (d, Float(feedback))]
        case .multiEcho: return (0...6).map { (d * $0, Float(pow(feedback, Double($0)))) }
        default:         return []
        }
    }

    private var kernel: [Float] {
        kind == .gaussian ? DSP.gaussianKernel(Int(length)) : DSP.movingAverageKernel(Int(length))
    }

    private func process(_ x: [Float]) -> [Float] {
        kind.isEcho ? DSP.sparseConvolve(x, taps: taps) : DSP.convolve(x, kernel: kernel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                Picker("Kernel", selection: $kind) { ForEach(KernelKind.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 240)
                    .onChange(of: kind) { _, k in source = k.isEcho ? .drums : .noisyTone }
                Picker("Input", selection: $source) { ForEach(AudioSource.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 220)
            }
            if kind.isEcho {
                HStack(spacing: 24) {
                    ParamSlider(title: "Delay", value: $delayMs, range: 40...400, format: { "\(Int($0)) ms" })
                    ParamSlider(title: "Echo gain", value: $feedback, range: 0.1...0.9, format: { String(format: "%.2f", $0) })
                }
            } else {
                ParamSlider(title: "Kernel length (taps)", value: $length, range: 1...101, step: 2, format: { "\(Int($0)) taps" })
            }
            HStack(spacing: 16) {
                LinePlot(series: [kernelSeries], xLabel: kind.isEcho ? "Delay (ms)" : "Tap", yLabel: "Weight", showPoints: true)
                    .frame(width: 240)
                LinePlot(series: signalSeries, xLabel: kind.isEcho ? "Time (s)" : "Time (ms)",
                         yLabel: kind.isEcho ? "Envelope" : "Amplitude")
            }
            .frame(height: 220)
            HStack {
                PlayButton("Play input") { source.samples(count: DemoAudio.toneCount) }
                PlayButton("Play convolved") { DSP.normalized(process(source.samples(count: DemoAudio.toneCount)), peak: 0.8) }
                StopButton()
            }
        }
    }

    private var kernelSeries: PlotSeries {
        if kind.isEcho {
            // Stems drawn as pairs of points down to zero.
            let pts = taps.flatMap { t -> [(x: Double, y: Double)] in
                let ms = Double(t.delay) / DemoAudio.fs * 1000
                return [(ms, 0), (ms, Double(t.gain)), (ms, 0)]
            }
            return PlotSeries(name: "Impulse response", points: pts, color: .series1)
        }
        return PlotSeries(name: "Impulse response", points: kernel.enumerated().map { (Double($0), Double($1)) }, color: .series1)
    }

    private var signalSeries: [PlotSeries] {
        if kind.isEcho {
            let x = source.samples(count: Int(DemoAudio.fs * 2)), y = process(x), blocks = 400
            func env(_ s: [Float]) -> [(x: Double, y: Double)] {
                DSP.envelope(s, blocks: blocks).enumerated().map { (Double($0) * 2 / Double(blocks), Double($1)) }
            }
            return [PlotSeries(name: "Input", points: env(x), color: .series2, dashed: true),
                    PlotSeries(name: "Output", points: env(y), color: .series1)]
        }
        let x = source.samples(count: 1600), y = process(x)
        return [.wave("Input", x, sampleRate: DemoAudio.fs, color: .series2, dashed: true),
                .wave("Output", y, sampleRate: DemoAudio.fs, color: .series1)]
    }
}

// MARK: - Lesson 8: Filter designer

struct FilterDesignerDemo: View {
    @State private var type = DSP.Biquad.Kind.lowPass
    @State private var logCutoff = log10(1000.0)
    @State private var q = 0.707
    @State private var gain = 9.0
    @State private var source = AudioSource.whiteNoise

    private var cutoff: Double { pow(10, logCutoff) }
    private var filter: DSP.Biquad { .init(type, cutoff: cutoff, q: q, gainDB: gain, sampleRate: DemoAudio.fs) }

    var body: some View {
        let f = filter
        let response = (0...240).map { i -> (x: Double, y: Double) in
            let hz = 20 * pow(1000, Double(i) / 240)            // 20 Hz … 20 kHz, log-spaced
            return (hz, max(f.responseDB(at: hz, sampleRate: DemoAudio.fs), -48))
        }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                Picker("Type", selection: $type) { ForEach(DSP.Biquad.Kind.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 200)
                Picker("Input", selection: $source) { ForEach(AudioSource.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 220)
            }
            HStack(spacing: 24) {
                ParamSlider(title: type == .lowPass || type == .highPass ? "Cutoff" : "Centre", value: $logCutoff,
                            range: log10(20)...log10(20000), format: { DemoAudio.formatHz(pow(10, $0)) })
                ParamSlider(title: "Q", value: $q, range: 0.3...12, format: { String(format: "%.2f", $0) })
                if type == .peak {
                    ParamSlider(title: "Gain", value: $gain, range: -18...18, format: { String(format: "%+.0f dB", $0) })
                }
            }
            LinePlot(series: [PlotSeries(name: "Frequency response", points: response, color: .series1)],
                     xLabel: "Frequency (Hz, log scale)", yLabel: "Gain (dB)", yDomain: -48...24, xDomain: 20...20000, xLog: true)
                .frame(height: 230)
            HStack {
                PlayButton("Play input") { source.samples(count: DemoAudio.toneCount) }
                PlayButton("Play filtered") { f.process(source.samples(count: DemoAudio.toneCount)) }
                StopButton()
                Spacer()
                Text(String(format: "b = [%.4f, %.4f, %.4f]   a = [1, %.4f, %.4f]", f.b0, f.b1, f.b2, f.a1, f.a2))
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}

// MARK: - Lesson 9: Compressor

struct CompressorDemo: View {
    @State private var threshold = -18.0
    @State private var ratio = 4.0
    @State private var attack = 5.0
    @State private var release = 120.0
    @State private var makeup = 6.0
    private static let seconds = 2.0

    private var comp: DSP.Compressor {
        .init(thresholdDB: threshold, ratio: ratio, attackMs: attack, releaseMs: release, makeupDB: makeup)
    }

    private func envDB(_ s: [Float], blocks: Int = 500) -> [(x: Double, y: Double)] {
        DSP.envelope(s, blocks: blocks).enumerated().map {
            (Double($0) * Self.seconds / Double(blocks), max(20 * log10(Double(max($1, 1e-6))), -48))
        }
    }

    var body: some View {
        let x = DSP.drumLoop(sampleRate: DemoAudio.fs, seconds: Self.seconds).map { $0 * 0.9 }
        let (y, gr) = comp.process(x, sampleRate: DemoAudio.fs)
        let transfer = stride(from: -48.0, through: 0, by: 1).map { ($0, comp.outputLevel(forInput: $0)) }
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    ParamSlider(title: "Threshold", value: $threshold, range: -40...0, format: { String(format: "%.0f dB", $0) })
                    ParamSlider(title: "Ratio", value: $ratio, range: 1...20, format: { String(format: "%.1f : 1", $0) })
                    ParamSlider(title: "Make-up gain", value: $makeup, range: 0...24, format: { String(format: "+%.0f dB", $0) })
                }
                GridRow {
                    ParamSlider(title: "Attack", value: $attack, range: 0.1...80, format: { String(format: "%.1f ms", $0) })
                    ParamSlider(title: "Release", value: $release, range: 10...600, format: { String(format: "%.0f ms", $0) })
                    Readout(label: "Max gain reduction", value: String(format: "%.1f dB", Double(gr.min() ?? 0)))
                }
            }
            HStack(spacing: 16) {
                LinePlot(series: [
                    PlotSeries(name: "1 : 1", points: [(-48, -48), (0, 0)], color: .secondary, dashed: true),
                    PlotSeries(name: "Compressor", points: transfer, color: .series1)
                ], xLabel: "Input (dBFS)", yLabel: "Output (dBFS)", yDomain: -48...24)
                .frame(width: 260)
                LinePlot(series: [
                    PlotSeries(name: "Before", points: envDB(x), color: .series2, dashed: true),
                    PlotSeries(name: "After", points: envDB(y), color: .series1)
                ], xLabel: "Time (s)", yLabel: "Peak level (dBFS)", yDomain: -48...12)
            }
            .frame(height: 240)
            HStack {
                PlayButton("Play before") { DSP.drumLoop(sampleRate: DemoAudio.fs, seconds: 4).map { $0 * 0.9 } }
                PlayButton("Play after") {
                    comp.process(DSP.drumLoop(sampleRate: DemoAudio.fs, seconds: 4).map { $0 * 0.9 }, sampleRate: DemoAudio.fs).output
                }
                StopButton()
                Spacer()
                Text("Output above 0 dBFS will clip — lower the make-up gain if you hear distortion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
