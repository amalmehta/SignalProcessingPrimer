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
