import SwiftUI

// MARK: - Lesson 4: Spectrum

struct SpectrumDemo: View {
    @State private var f: [Double] = [440, 1320, 3000]
    @State private var a: [Double] = [0.8, 0.4, 0]
    @State private var noise = 0.0
    @State private var waveform = DSP.Waveform.sine
    private let n = 4096

    private func signal(_ count: Int) -> [Float] {
        var x = [Float](repeating: 0, count: count)
        for i in 0..<3 where a[i] > 0 {
            let t = DSP.tone(i == 0 ? waveform : .sine, frequency: f[i], amplitude: a[i], sampleRate: DemoAudio.fs, count: count)
            x = zip(x, t).map(+)
        }
        if noise > 0 { x = zip(x, DSP.noise(count: count)).map { $0 + Float(noise) * $1 } }
        return x
    }

    var body: some View {
        let x = signal(n)
        let mags = DSP.decibels(DSP.magnitudeSpectrum(x, window: .hann), floor: -90)
        let binHz = DemoAudio.fs / Double(n)
        let maxBin = Int(6000 / binHz)
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    GridRow {
                        Text("Tone \(i + 1)").font(.callout.weight(.medium))
                        ParamSlider(title: "Frequency", value: $f[i], range: 50...5500, format: { DemoAudio.formatHz($0) })
                        ParamSlider(title: "Amplitude", value: $a[i], range: 0...1, format: { String(format: "%.2f", $0) })
                    }
                }
                GridRow {
                    Picker("Tone 1 shape", selection: $waveform) {
                        ForEach(DSP.Waveform.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .gridCellColumns(2)
                    ParamSlider(title: "Noise", value: $noise, range: 0...0.5, format: { String(format: "%.2f", $0) })
                }
            }
            HStack(spacing: 16) {
                LinePlot(series: [.wave("Signal", Array(x.prefix(441)), sampleRate: DemoAudio.fs, color: .series2)],
                         xLabel: "Time (ms)", yLabel: "Amplitude")
                LinePlot(series: [PlotSeries(name: "Spectrum",
                                             points: (1...maxBin).map { (Double($0) * binHz, Double(mags[$0])) },
                                             color: .series1)],
                         xLabel: "Frequency (Hz)", yLabel: "Level (dB)", yDomain: -90...0)
            }
            .frame(height: 220)
            HStack {
                PlayButton { DSP.normalized(signal(DemoAudio.toneCount), peak: 0.6) }
                StopButton()
                Spacer()
                Text("FFT size \(n) · bins every \(String(format: "%.1f", binHz)) Hz · Hann window")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Lesson 5: Windows & leakage

struct WindowingDemo: View {
    @State private var bin = 10.0
    @State private var window = DSP.Window.rectangular
    @State private var quietTone = true
    private let n = 128

    var body: some View {
        // Frequencies in "bins" so integer vs. between-bin is obvious; fs is nominal here.
        let fs = Double(n)
        let x = zip(DSP.tone(frequency: bin, sampleRate: fs, count: n),
                    DSP.tone(frequency: 30, amplitude: quietTone ? 0.003 : 0, sampleRate: fs, count: n)).map(+)
        let spec = DSP.decibels(DSP.magnitudeSpectrum(x, window: window), floor: -100)
        let w = window.coefficients(n)
        let leakage = spec[45...].max() ?? -100
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                ParamSlider(title: "Tone position (bins)", value: $bin, range: 6...14, format: { String(format: "%.2f", $0) })
                Picker("Window", selection: $window) { ForEach(DSP.Window.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 220)
                Toggle("Quiet tone at bin 30 (−50 dB)", isOn: $quietTone).toggleStyle(.switch)
            }
            HStack(spacing: 32) {
                Readout(label: "Whole cycles in the frame", value: bin.rounded() == bin ? "Yes" : "No")
                Readout(label: "Leakage far from the tone (bins 45+)", value: String(format: "%.0f dB", leakage))
                Button("Snap to a bin") { bin = bin.rounded() }
                Button("Halfway between bins") { bin = bin.rounded(.down) + 0.5 }
            }
            HStack(spacing: 16) {
                LinePlot(series: [
                    PlotSeries(name: "Window", points: w.enumerated().map { (Double($0), Double($1)) }, color: .series2, dashed: true),
                    PlotSeries(name: "Windowed signal", points: zip(x, w).enumerated().map { (Double($0), Double($1.0 * $1.1)) }, color: .series1)
                ], xLabel: "Sample", yLabel: "Amplitude", yDomain: -1.05...1.05)
                .frame(maxWidth: 320)
                LinePlot(series: [PlotSeries(name: "Spectrum", points: spec.enumerated().map { (Double($0), Double($1)) }, color: .series1)],
                         xLabel: "Bin", yLabel: "Level (dB)", yDomain: -100...0, showPoints: true)
            }
            .frame(height: 230)
        }
    }
}

// MARK: - Lesson 6: Spectrogram

struct SpectrogramDemo: View {
    enum Source: String, CaseIterable, Identifiable {
        case sweep = "Rising sweep", clicksAndTones = "Clicks + steady tones", melody = "Melody with harmonics"
        var id: String { rawValue }
    }
    @State private var source = Source.melody
    @State private var frameSize = 1024
    @Environment(\.colorScheme) private var scheme
    private static let seconds = 2.0
    private static let maxHz = 8000.0

    private func signal() -> [Float] {
        let fs = DemoAudio.fs, count = Int(fs * Self.seconds)
        switch source {
        case .sweep:
            return DSP.chirp(from: 100, to: 7500, sampleRate: fs, count: count).map { $0 * 0.6 }
        case .clicksAndTones:
            var x = DSP.mix([.init(frequency: 600, amplitude: 0.25), .init(frequency: 680, amplitude: 0.25),
                             .init(frequency: 3000, amplitude: 0.15)], sampleRate: fs, count: count)
            for c in stride(from: Int(fs * 0.1), to: count, by: Int(fs * 0.3)) { x[c] += 0.9; x[c + 1] -= 0.6 }
            return x
        case .melody:
            let notes: [Double] = [262, 330, 392, 523, 392, 330, 294, 262]
            let per = count / notes.count
            return notes.enumerated().flatMap { i, f -> [Float] in
                let tone = DSP.mix((1...6).map { .init(frequency: f * Double($0), amplitude: 0.3 / Double($0)) },
                                   sampleRate: fs, count: per)
                // 5 ms fades at each end of a note so note changes don't add broadband clicks.
                let fade = fs * 0.005
                return tone.enumerated().map { n, v in
                    v * Float(min(1, Double(n) / fade, Double(per - n) / fade) * exp(-Double(n) / fs * 4))
                }
            }
        }
    }

    var body: some View {
        let x = signal()
        let hop = max(frameSize / 4, x.count / 600)
        let columns = DSP.spectrogram(x, frameSize: frameSize, hop: hop)
        let binHz = DemoAudio.fs / Double(frameSize)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                Picker("Signal", selection: $source) { ForEach(Source.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 300)
                Picker("Window size", selection: $frameSize) {
                    ForEach([64, 128, 256, 512, 1024, 2048, 4096], id: \.self) { Text("\($0)").tag($0) }
                }
                .frame(width: 200)
            }
            HStack(spacing: 32) {
                Readout(label: "Time per column (window length)", value: String(format: "%.1f ms", Double(frameSize) / DemoAudio.fs * 1000))
                Readout(label: "Frequency resolution", value: String(format: "%.1f Hz", binHz))
            }
            HStack(alignment: .top, spacing: 8) {
                VStack {
                    Text("8 kHz"); Spacer(); Text("4 kHz"); Spacer(); Text("0")
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(height: 240)
                VStack(spacing: 4) {
                    if let img = SpectrogramRenderer.image(columns: columns, maxBin: Int(Self.maxHz / binHz), dark: scheme == .dark) {
                        Image(decorative: img, scale: 1).resizable().interpolation(.none)
                            .frame(height: 240).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel("Spectrogram of \(source.rawValue)")
                    }
                    HStack { Text("0 s"); Spacer(); Text("Time"); Spacer(); Text(String(format: "%.0f s", Self.seconds)) }
                        .font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("0 dB").font(.caption2).foregroundStyle(.secondary)
                    LinearGradient(colors: SpectrogramRenderer.ramp(dark: scheme == .dark).reversed().map { Color(nsColor: $0) },
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: 12, height: 196).clipShape(RoundedRectangle(cornerRadius: 3))
                    Text("−90 dB").font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Level scale from −90 dB to 0 dB")
            }
            HStack {
                PlayButton("Play signal") { x }
                StopButton()
            }
        }
    }
}

/// Paints dB columns using the sequential blue ramp (low level recedes toward the background).
enum SpectrogramRenderer {
    static func ramp(dark: Bool) -> [NSColor] {
        let light = ["#f7fbff", "#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"]
        let darkSteps = ["#1a1a19", "#0d366b", "#184f95", "#256abf", "#3987e5", "#6da7ec", "#9ec5f4", "#cde2fb"]
        return (dark ? darkSteps : light).map(NSColor.init(hex:))
    }

    static func image(columns: [[Float]], maxBin: Int, dark: Bool, floorDB: Float = -90) -> CGImage? {
        guard let first = columns.first else { return nil }
        let w = columns.count, h = min(maxBin, first.count - 1)
        guard h > 0 else { return nil }
        let stops = ramp(dark: dark).map { c -> (Float, Float, Float) in
            let s = c.usingColorSpace(.sRGB)!
            return (Float(s.redComponent), Float(s.greenComponent), Float(s.blueComponent))
        }
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for (x, col) in columns.enumerated() {
            for row in 0..<h {
                let bin = h - row                       // low frequencies at the bottom
                let t = min(max((col[bin] - floorDB) / -floorDB, 0), 1) * Float(stops.count - 1)
                let i = min(Int(t), stops.count - 2), f = t - Float(i)
                let a = stops[i], b = stops[i + 1]
                let o = (row * w + x) * 4
                px[o] = UInt8((a.0 + (b.0 - a.0) * f) * 255)
                px[o + 1] = UInt8((a.1 + (b.1 - a.1) * f) * 255)
                px[o + 2] = UInt8((a.2 + (b.2 - a.2) * f) * 255)
            }
        }
        return px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
    }
}
