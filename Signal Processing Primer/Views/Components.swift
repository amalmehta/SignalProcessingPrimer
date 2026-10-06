import AppKit
import Charts
import SwiftUI

// MARK: - Palette (validated categorical pair + sequential blue, light & dark steps)

extension Color {
    private static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
    /// Series 1 — the processed / main signal.
    static let series1 = dynamic(light: "#2a78d6", dark: "#3987e5")
    /// Series 2 — the reference / original signal.
    static let series2 = dynamic(light: "#eb6834", dark: "#d95926")
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
}

extension NSColor {
    convenience init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Controls

/// A labelled slider with its current value shown on the right.
struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(format(value)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let step { Slider(value: $value, in: range, step: step) } else { Slider(value: $value, in: range) }
        }
    }
}

/// Plays a sound produced on demand. Shows Stop while playing.
struct PlayButton: View {
    let title: String
    let samples: () -> [Float]
    @ObservedObject private var player = TonePlayer.shared
    @AppStorage(Prefs.volume) private var volume = 0.5

    init(_ title: String = "Play", samples: @escaping () -> [Float]) {
        self.title = title; self.samples = samples
    }

    var body: some View {
        Button {
            player.play(samples(), volume: volume)
        } label: {
            Label(title, systemImage: "speaker.wave.2.fill")
        }
    }
}

struct StopButton: View {
    @ObservedObject private var player = TonePlayer.shared
    var body: some View {
        Button { player.stop() } label: { Label("Stop", systemImage: "stop.fill") }
            .disabled(!player.isPlaying)
    }
}

/// A single readout: big number + caption.
struct Readout: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Charts

struct PlotSeries: Identifiable {
    let id = UUID()
    let name: String
    let points: [(x: Double, y: Double)]
    let color: Color
    var dashed = false
}

/// Line chart for one or more series with a shared x axis. Legend appears only for ≥ 2 series.
/// Hovering shows a crosshair with each series' value at that x.
struct LinePlot: View {
    let series: [PlotSeries]
    var xLabel: String
    var yLabel: String
    var yDomain: ClosedRange<Double>? = nil
    var xDomain: ClosedRange<Double>? = nil
    var xLog = false
    var showPoints = false
    @State private var hoverX: Double?

    var body: some View {
        let chart = Chart {
            ForEach(series) { s in
                ForEach(Array(s.points.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value(xLabel, p.x), y: .value(yLabel, p.y), series: .value("Series", s.name))
                        .foregroundStyle(by: .value("Series", s.name))
                        .lineStyle(StrokeStyle(lineWidth: s.dashed ? 1.5 : 2, dash: s.dashed ? [4, 3] : []))
                        .interpolationMethod(.linear)
                    if showPoints && !s.dashed {
                        PointMark(x: .value(xLabel, p.x), y: .value(yLabel, p.y))
                            .foregroundStyle(by: .value("Series", s.name))
                            .symbolSize(28)
                    }
                }
            }
            if let hoverX {
                RuleMark(x: .value(xLabel, hoverX))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(at: hoverX)
                    }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartLegend(series.count > 1 ? .visible : .hidden)
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
        .chartYScale(domain: yDomain ?? autoY)
        .chartXScale(domain: xDomain ?? autoX, type: xLog ? .log : .linear)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            guard let frame = proxy.plotFrame else { return }
                            let origin = geo[frame].origin
                            hoverX = proxy.value(atX: loc.x - origin.x, as: Double.self)
                        case .ended:
                            hoverX = nil
                        }
                    }
            }
        }
        chart
    }

    private var autoX: ClosedRange<Double> {
        let xs = series.flatMap { $0.points.map(\.x) }
        guard let lo = xs.min(), let hi = xs.max(), hi > lo else { return 0...1 }
        return lo...hi
    }

    private var autoY: ClosedRange<Double> {
        let ys = series.flatMap { $0.points.map(\.y) }
        guard let lo = ys.min(), let hi = ys.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.08, 1e-3)
        return (lo - pad)...(hi + pad)
    }

    private func tooltip(at x: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(xLabel): \(Self.format(x))").font(.caption2).foregroundStyle(.secondary)
            ForEach(series) { s in
                if let p = s.points.min(by: { abs($0.x - x) < abs($1.x - x) }) {
                    HStack(spacing: 4) {
                        Circle().fill(s.color).frame(width: 7, height: 7)
                        Text("\(series.count > 1 ? s.name + ": " : "")\(Self.format(p.y))").font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    static func format(_ v: Double) -> String {
        abs(v) >= 100 ? String(format: "%.0f", v) : abs(v) >= 1 ? String(format: "%.2f", v) : String(format: "%.3f", v)
    }
}

extension PlotSeries {
    /// Time-domain series from samples, decimated for drawing; x in milliseconds.
    static func wave(_ name: String, _ x: [Float], sampleRate: Double, color: Color, dashed: Bool = false) -> PlotSeries {
        PlotSeries(name: name, points: DSP.decimateForPlot(x).map { (Double($0.0) / sampleRate * 1000, Double($0.1)) },
                   color: color, dashed: dashed)
    }
}

/// Wraps a demo in a card with a caption.
struct DemoCard<Content: View>: View {
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Try it", systemImage: "hand.tap").font(.headline)
            Text(caption).font(.callout).foregroundStyle(.secondary)
            content
        }
        .padding(18)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

/// Shows a GrayImage at its pixel aspect ratio.
struct GrayImageView: View {
    let image: GrayImage
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            if let cg = image.cgImage {
                Image(decorative: cg, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
