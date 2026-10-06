import SwiftUI

/// Loads the user's chosen image (Settings → Images) or the built-in test card.
enum DemoImage {
    @MainActor private static var cache: (path: String, image: GrayImage)?

    @MainActor static func current() -> GrayImage {
        let path = UserDefaults.standard.string(forKey: Prefs.customImagePath) ?? ""
        if let cache, cache.path == path { return cache.image }
        let img = path.isEmpty ? ImageDSP.testCard() : (ImageDSP.load(url: URL(fileURLWithPath: path)) ?? ImageDSP.testCard())
        cache = (path, img)
        return img
    }
}

// MARK: - Lesson 10: Image kernels

struct ImageKernelsDemo: View {
    @State private var kernel = ImageDSP.Kernel.gaussian
    @State private var strength = 2.0
    @State private var output: GrayImage?
    @AppStorage(Prefs.customImagePath) private var imagePath = ""

    private var usesStrength: Bool { [.boxBlur, .gaussian, .sharpen].contains(kernel) }

    var body: some View {
        let input = DemoImage.current()
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                Picker("Kernel", selection: $kernel) { ForEach(ImageDSP.Kernel.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 280)
                ParamSlider(title: "Strength", value: $strength, range: 1...4, step: 1, format: { "\(Int($0))" })
                    .disabled(!usesStrength).opacity(usesStrength ? 1 : 0.4)
            }
            HStack(alignment: .top, spacing: 16) {
                GrayImageView(image: input, label: "Original")
                if let output { GrayImageView(image: output, label: kernel.rawValue) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
                KernelMatrixView(matrix: kernel.matrix(strength: Int(strength))).frame(width: 190)
            }
            .frame(maxHeight: 340)
        }
        .task(id: "\(kernel.rawValue)-\(strength)-\(imagePath)") {
            let k = kernel, s = Int(strength)
            output = await Task.detached(priority: .userInitiated) { ImageDSP.apply(k, strength: s, to: input) }.value
        }
    }
}

/// Shows small kernels as a grid of weights, large ones as a size label.
struct KernelMatrixView: View {
    let matrix: [[Float]]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kernel").font(.caption).foregroundStyle(.secondary)
            if matrix.count <= 3 {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(0..<matrix.count, id: \.self) { r in
                        GridRow {
                            ForEach(0..<matrix[r].count, id: \.self) { c in
                                Text(format(matrix[r][c]))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 48, height: 30)
                                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }
            } else {
                Text("\(matrix.count) × \(matrix.count) weights summing to 1 — each output pixel averages \(matrix.count * matrix.count) neighbours.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func format(_ v: Float) -> String { v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.2f", v) }
}

// MARK: - Lesson 11: JPEG

struct JPEGDemo: View {
    @State private var quality = 30.0
    @State private var zoom = false
    @State private var result: ImageDSP.JPEGResult?
    @AppStorage(Prefs.customImagePath) private var imagePath = ""

    var body: some View {
        let input = DemoImage.current()
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                ParamSlider(title: "JPEG quality", value: $quality, range: 1...100, step: 1, format: { "\(Int($0))" })
                Toggle("Zoom 2× on centre", isOn: $zoom).toggleStyle(.switch)
            }
            HStack(spacing: 32) {
                Readout(label: "Coefficients quantized to zero", value: result.map { String(format: "%.0f%%", $0.zeroFraction * 100) } ?? "…")
                Readout(label: "Quality (PSNR, higher is better)", value: result.map { String(format: "%.1f dB", $0.psnr) } ?? "…")
                Readout(label: "Block size", value: "8 × 8")
            }
            HStack(alignment: .top, spacing: 16) {
                GrayImageView(image: zoom ? crop(input) : input, label: "Original")
                if let result { GrayImageView(image: zoom ? crop(result.image) : result.image, label: "After DCT → quantize → inverse DCT") }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            }
            .frame(maxHeight: 360)
        }
        .task(id: "\(Int(quality))-\(imagePath)") {
            let q = Int(quality)
            result = await Task.detached(priority: .userInitiated) { ImageDSP.jpegRoundTrip(input, quality: q) }.value
        }
    }

    private func crop(_ img: GrayImage) -> GrayImage {
        let w = img.width / 2, h = img.height / 2, x0 = img.width / 4, y0 = img.height / 4
        var px = [Float](); px.reserveCapacity(w * h)
        for y in 0..<h { for x in 0..<w { px.append(img[x0 + x, y0 + y]) } }
        return GrayImage(width: w, height: h, pixels: px)
    }
}

// MARK: - Lesson 12: Frame rate & shutter

struct FrameRateDemo: View {
    @State private var revsPerSecond = 2.0
    @State private var fps = 24.0
    @State private var shutterAngle = 180.0
    @State private var start = Date()
    private let spokes = 8

    /// How the wheel appears to move, in revolutions per second (negative = backwards).
    private var apparentSpeed: Double {
        let spokeAdvance = revsPerSecond * Double(spokes) / fps      // spoke spacings per frame
        let wrapped = spokeAdvance - spokeAdvance.rounded()          // nearest-match interpretation, -0.5…0.5
        return wrapped * fps / Double(spokes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                ParamSlider(title: "Wheel speed", value: $revsPerSecond, range: 0...8, step: 0.125,
                            format: { String(format: "%.2f rev/s", $0) })
                Picker("Frame rate", selection: $fps) {
                    ForEach([12.0, 24, 25, 30, 60], id: \.self) { Text("\(Int($0)) fps").tag($0) }
                }
                .frame(width: 160)
                ParamSlider(title: "Shutter angle", value: $shutterAngle, range: 1...360, step: 1,
                            format: { "\(Int($0))°" })
            }
            HStack(spacing: 32) {
                Readout(label: "Exposure per frame", value: "1/\(Int((360 / shutterAngle * fps).rounded())) s")
                Readout(label: "Looks like it turns at", value: String(format: "%.2f rev/s", apparentSpeed))
                Label(verdict.text, systemImage: verdict.icon).foregroundStyle(verdict.color)
            }
            HStack(spacing: 24) {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    let frameTime = (t * fps).rounded(.down) / fps        // the camera only sees these instants
                    Canvas { ctx, size in drawWheel(ctx, size: size, frameTime: frameTime) }
                }
                .frame(width: 260, height: 260)
                .accessibilityLabel("Animated wheel as filmed by the camera")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try these").font(.headline)
                    preset("Frozen: 3 rev/s at 24 fps", rps: 3, fps: 24, angle: 180)
                    preset("Backwards: 2.75 rev/s at 24 fps", rps: 2.75, fps: 24, angle: 45)
                    preset("Same speed, 60 fps", rps: 2.75, fps: 60, angle: 180)
                    preset("Heavy blur: 360° shutter", rps: 1.5, fps: 24, angle: 360)
                    Text("The wheel has \(spokes) identical spokes, so any rotation that's a multiple of 1/\(spokes) revolution per frame is indistinguishable from standing still.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var verdict: (text: String, icon: String, color: Color) {
        if revsPerSecond == 0 { return ("Stationary", "pause.circle", .secondary) }
        if abs(apparentSpeed) < 0.01 { return ("Appears frozen", "snowflake", .orange) }
        if apparentSpeed < 0 { return ("Appears to spin backwards", "arrow.counterclockwise", .orange) }
        if abs(apparentSpeed - revsPerSecond) > 0.01 { return ("Appears slower than it is", "tortoise", .orange) }
        return ("Looks correct", "checkmark.circle", .green)
    }

    private func preset(_ title: String, rps: Double, fps: Double, angle: Double) -> some View {
        Button(title) { revsPerSecond = rps; self.fps = fps; shutterAngle = angle }.buttonStyle(.link)
    }

    private func drawWheel(_ ctx: GraphicsContext, size: CGSize, frameTime: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2 - 6
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                   with: .color(.secondary), lineWidth: 4)
        // Motion blur: average sub-frames spread across the open-shutter interval.
        let exposure = shutterAngle / 360 / fps
        let subframes = max(1, Int(shutterAngle / 10))
        var layer = ctx
        layer.opacity = min(1, 1.6 / Double(subframes).squareRoot())
        for s in 0..<subframes {
            let t = frameTime + exposure * Double(s) / Double(subframes)
            let base = 2 * Double.pi * revsPerSecond * t
            var spokesPath = Path()
            for k in 0..<spokes {
                let a = base + 2 * .pi * Double(k) / Double(spokes)
                spokesPath.move(to: c)
                spokesPath.addLine(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
            }
            // Spokes are deliberately identical: that symmetry is what lets the wheel alias.
            layer.stroke(spokesPath, with: .color(.series1), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)), with: .color(.secondary))
    }
}

// MARK: - Lesson 13: Colour & gamma

extension DemoImage {
    @MainActor private static var colourCache: (path: String, image: RGBImage)?

    /// Colour version of the demo image (Settings → Images), or the colour test card.
    @MainActor static func currentColour() -> RGBImage {
        let path = UserDefaults.standard.string(forKey: Prefs.customImagePath) ?? ""
        if let colourCache, colourCache.path == path { return colourCache.image }
        let img = path.isEmpty ? ColourDSP.colourCard() : (ColourDSP.load(url: URL(fileURLWithPath: path)) ?? ColourDSP.colourCard())
        colourCache = (path, img)
        return img
    }
}

struct RGBImageView: View {
    let image: RGBImage
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

struct ColourGammaDemo: View {
    enum Part: String, CaseIterable, Identifiable { case gamma = "Gamma", chroma = "Chroma subsampling"; var id: String { rawValue } }
    @State private var part = Part.gamma

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Part", selection: $part) { ForEach(Part.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
            switch part {
            case .gamma: GammaPart()
            case .chroma: ChromaPart()
            }
        }
    }
}

private struct GammaPart: View {
    @State private var transfer = ColourDSP.Transfer.sRGB
    @State private var bits = 5.0

    var body: some View {
        let b = Int(bits)
        let curve = (0...100).map { i -> (x: Double, y: Double) in (Double(i) / 100, transfer.encode(Double(i) / 100)) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                Picker("Transfer function", selection: $transfer) {
                    ForEach(ColourDSP.Transfer.allCases.filter { $0 != .linear }) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 300)
                ParamSlider(title: "Bit depth", value: $bits, range: 2...8, step: 1, format: { "\(Int($0)) bits (\(1 << Int($0)) levels)" })
            }
            HStack(spacing: 32) {
                Readout(label: "Codes for the darkest 10% of light, stored linearly",
                        value: "\(ColourDSP.codesBelow(0.1, bits: b, transfer: .linear))")
                Readout(label: "…stored with \(transfer.rawValue)",
                        value: "\(ColourDSP.codesBelow(0.1, bits: b, transfer: transfer))")
            }
            HStack(alignment: .top, spacing: 20) {
                LinePlot(series: [
                    PlotSeries(name: "Linear (no gamma)", points: [(0, 0), (1, 1)], color: .secondary, dashed: true),
                    PlotSeries(name: transfer.rawValue, points: curve, color: .series1)
                ], xLabel: "Linear light", yLabel: "Stored value", yDomain: 0...1, xDomain: 0...1)
                .frame(width: 280, height: 240)
                VStack(alignment: .leading, spacing: 10) {
                    ramp("Stored linearly — shadows band, highlights waste codes", .linear, bits: b)
                    ramp("Stored with \(transfer.rawValue) — steps look even", transfer, bits: b)
                    ramp("Reference: smooth ramp (8-bit sRGB)", .sRGB, bits: 8)
                    Text("Each strip shows the same ramp of light, dark to bright, after storing it at \(b) bits.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func ramp(_ label: String, _ t: ColourDSP.Transfer, bits: Int) -> some View {
        let light = ColourDSP.storedRamp(count: 512, bits: bits, transfer: t)
        // Screens expect sRGB-encoded values, so encode the emitted light for display.
        let px = light.map { Float(ColourDSP.Transfer.sRGB.encode($0)) }
        let strip = RGBImage(width: 512, height: 1, r: px, g: px, b: px)
        return VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption)
            if let cg = strip.cgImage {
                Image(decorative: cg, scale: 1).resizable().interpolation(.none)
                    .frame(height: 34).clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel(label)
            }
        }
    }
}

private struct ChromaPart: View {
    @State private var mode = ColourDSP.Subsampling.s420
    @State private var channel = ColourDSP.Channel.result
    @State private var zoom = true
    @State private var output: (view: RGBImage, psnr: Double)?
    @AppStorage(Prefs.customImagePath) private var imagePath = ""

    var body: some View {
        let input = DemoImage.currentColour()
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                Picker("Subsampling", selection: $mode) { ForEach(ColourDSP.Subsampling.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 260)
                Picker("Show", selection: $channel) { ForEach(ColourDSP.Channel.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 240)
                Toggle("Zoom 2× on centre", isOn: $zoom).toggleStyle(.switch)
            }
            HStack(spacing: 32) {
                Readout(label: "Samples stored per pixel (4:4:4 = 3)", value: String(format: "%.1f", mode.samplesPerPixel))
                Readout(label: "Data vs 4:4:4", value: String(format: "%.0f%%", mode.samplesPerPixel / 3 * 100))
                Readout(label: "Quality (PSNR, higher is better)", value: output.map { $0.psnr.isInfinite ? "lossless" : String(format: "%.1f dB", $0.psnr) } ?? "…")
            }
            HStack(alignment: .top, spacing: 16) {
                RGBImageView(image: zoom ? input.centreCrop() : input, label: "Original (4:4:4)")
                if let output { RGBImageView(image: zoom ? output.view.centreCrop() : output.view, label: "\(mode.rawValue) · \(channel.rawValue)") }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            }
            .frame(maxHeight: 360)
        }
        .task(id: "\(mode.rawValue)-\(channel.rawValue)-\(imagePath)") {
            let m = mode, c = channel
            output = await Task.detached(priority: .userInitiated) {
                let r = ColourDSP.subsample(input, m)
                return (ColourDSP.channelView(c, result: r.image, y: r.y, cb: r.cb, cr: r.cr), ColourDSP.psnr(input, r.image))
            }.value
        }
    }
}
