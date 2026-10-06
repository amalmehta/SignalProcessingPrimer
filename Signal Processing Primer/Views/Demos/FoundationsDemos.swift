import SwiftUI

// MARK: - Lesson 1: Sine mixer

struct SineMixerDemo: View {
    enum Preset: String, CaseIterable, Identifiable {
        case pure = "Pure sine", square = "Square-ish", sawtooth = "Sawtooth-ish", triangle = "Triangle-ish", custom = "Custom"
        var id: String { rawValue }
    }
    static let harmonicCount = 8

    @State private var fundamental = 220.0
    @State private var amps: [Double] = [1, 0, 0, 0, 0, 0, 0, 0]
    @State private var signs: [Double] = Array(repeating: 1, count: harmonicCount)
    @State private var preset = Preset.pure

    private var partials: [DSP.Partial] {
        (0..<Self.harmonicCount).map { i in
            DSP.Partial(frequency: fundamental * Double(i + 1), amplitude: amps[i] * signs[i])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    ParamSlider(title: "Fundamental", value: $fundamental, range: 55...880,
                                format: { DemoAudio.formatHz($0) })
                    Picker("Recipe", selection: $preset) { ForEach(Preset.allCases) { Text($0.rawValue).tag($0) } }
                        .onChange(of: preset) { _, p in apply(p) }
                }
                .frame(width: 260)
                harmonicSliders
            }
            let periods = 2.0, count = Int(DemoAudio.fs * periods / fundamental)
            LinePlot(series: [.wave("Mix", DSP.mix(partials, sampleRate: DemoAudio.fs, count: count),
                                    sampleRate: DemoAudio.fs, color: .series1)],
                     xLabel: "Time (ms)", yLabel: "Amplitude", yDomain: -2...2)
                .frame(height: 200)
            HStack {
                PlayButton {
                    DSP.normalized(DSP.mix(partials, sampleRate: DemoAudio.fs, count: DemoAudio.toneCount), peak: 0.6)
                }
                StopButton()
                Spacer()
                Text("Showing two cycles of the fundamental").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var harmonicSliders: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(0..<Self.harmonicCount, id: \.self) { i in
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { amps[i] }, set: { amps[i] = $0; preset = .custom }), in: 0...1)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 90, height: 24)
                        .frame(width: 26, height: 90)
                    Text("\(i + 1)×").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Harmonic \(i + 1)")
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Harmonic amplitudes").font(.caption).foregroundStyle(.secondary).offset(y: -16)
        }
        .padding(.top, 16)
    }

    private func apply(_ p: Preset) {
        let n = (1...Self.harmonicCount).map(Double.init)
        switch p {
        case .pure:     amps = n.map { $0 == 1 ? 1 : 0 }; signs = n.map { _ in 1 }
        case .square:   amps = n.map { Int($0) % 2 == 1 ? 1 / $0 : 0 }; signs = n.map { _ in 1 }
        case .sawtooth: amps = n.map { 1 / $0 }; signs = n.map { Int($0) % 2 == 1 ? 1 : -1 }
        case .triangle: amps = n.map { Int($0) % 2 == 1 ? 1 / ($0 * $0) : 0 }
                        signs = n.map { Int($0) % 4 == 1 ? 1 : -1 }
        case .custom:   break
        }
    }
}

// MARK: - Lesson 2: Aliasing

struct AliasingDemo: View {
    @State private var sampleRate = 8000.0
    @State private var frequency = 1000.0

    private var alias: Double { DSP.aliasedFrequency(frequency, sampleRate: sampleRate) }
    private var folds: Bool { frequency.truncatingRemainder(dividingBy: sampleRate) > sampleRate / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                Picker("Sample rate", selection: $sampleRate) {
                    Text("8 kHz (telephone)").tag(8000.0)
                    Text("16 kHz").tag(16000.0)
                    Text("44.1 kHz (CD)").tag(44100.0)
                }
                .frame(width: 260)
                .onChange(of: sampleRate) { _, fs in frequency = min(frequency, 2 * fs) }
                ParamSlider(title: "Input tone", value: $frequency, range: 50...(2 * sampleRate),
                            format: { DemoAudio.formatHz($0) })
            }
            HStack(spacing: 32) {
                Readout(label: "Nyquist (fs / 2)", value: DemoAudio.formatHz(sampleRate / 2))
                Readout(label: "Frequency the samples contain", value: DemoAudio.formatHz(alias))
                Label(abs(alias - frequency) < 0.5 ? "Captured faithfully" : "Aliased!",
                      systemImage: abs(alias - frequency) < 0.5 ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(abs(alias - frequency) < 0.5 ? Color.green : Color.orange)
            }
            LinePlot(series: series, xLabel: "Time (ms)", yLabel: "Amplitude", yDomain: -1.2...1.2, showPoints: true)
                .frame(height: 220)
            HStack {
                PlayButton("Play what was recorded") {
                    DSP.tone(frequency: alias, amplitude: 0.5, sampleRate: DemoAudio.fs, count: DemoAudio.toneCount)
                }
                PlayButton("Play the true tone") {
                    DSP.tone(frequency: frequency, amplitude: 0.5, sampleRate: DemoAudio.fs, count: DemoAudio.toneCount)
                }
                .disabled(frequency > 20000)
                .help(frequency > 20000 ? "Above human hearing (and above what this Mac can play)" : "")
                StopButton()
            }
        }
    }

    private var series: [PlotSeries] {
        let samplesShown = 24, duration = Double(samplesShown) / sampleRate
        let fine = 480
        let truth = (0..<fine).map { i -> (x: Double, y: Double) in
            let t = duration * Double(i) / Double(fine)
            return (t * 1000, sin(2 * .pi * frequency * t))
        }
        // The alias curve passes exactly through every sample; it is mirrored when the tone folds.
        let sign = folds ? -1.0 : 1.0
        let samples = (0...samplesShown).map { n -> (x: Double, y: Double) in
            let t = Double(n) / sampleRate
            return (t * 1000, sin(2 * .pi * frequency * t))
        }
        let aliasCurve = (0..<fine).map { i -> (x: Double, y: Double) in
            let t = duration * Double(i) / Double(fine)
            return (t * 1000, sign * sin(2 * .pi * alias * t))
        }
        return [
            PlotSeries(name: "True signal", points: truth, color: .secondary.opacity(0.5), dashed: true),
            PlotSeries(name: "Samples → reconstructed", points: aliasCurve, color: .series2, dashed: true),
            PlotSeries(name: "Samples", points: samples, color: .series1)
        ]
    }
}

// MARK: - Lesson 3: Quantization

struct QuantizationDemo: View {
    @State private var bits = 4.0
    @State private var dither = false
    @State private var level = 0.5

    private func source(_ count: Int) -> [Float] {
        DSP.tone(frequency: 220, amplitude: level, sampleRate: DemoAudio.fs, count: count)
    }

    var body: some View {
        let shown = source(Int(DemoAudio.fs * 2 / 220))
        let q = DSP.quantize(shown, bits: Int(bits), dither: dither)
        let long = source(16384)
        let snr = DSP.snr(reference: long, processed: DSP.quantize(long, bits: Int(bits), dither: dither))
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                ParamSlider(title: "Bit depth", value: $bits, range: 1...16, step: 1, format: { "\(Int($0)) bits" })
                ParamSlider(title: "Signal level", value: $level, range: 0.02...0.95,
                            format: { String(format: "%.0f dBFS", 20 * log10($0)) })
                Toggle("Dither", isOn: $dither).toggleStyle(.switch)
            }
            HStack(spacing: 32) {
                Readout(label: "Levels available", value: (1 << Int(bits)).formatted())
                Readout(label: "Theoretical dynamic range", value: String(format: "%.0f dB", 6.02 * bits + 1.76))
                Readout(label: "Measured signal-to-noise", value: String(format: "%.1f dB", snr))
            }
            LinePlot(series: [
                .wave("Original", shown, sampleRate: DemoAudio.fs, color: .series2, dashed: true),
                .wave("Quantized", q, sampleRate: DemoAudio.fs, color: .series1)
            ], xLabel: "Time (ms)", yLabel: "Amplitude", yDomain: -1...1)
            .frame(height: 220)
            HStack {
                PlayButton("Play original") { source(DemoAudio.toneCount) }
                PlayButton("Play quantized") { DSP.quantize(source(DemoAudio.toneCount), bits: Int(bits), dither: dither) }
                StopButton()
            }
        }
    }
}
