import AppKit
import CoreGraphics
import Foundation

/// An RGB image with gamma-encoded (R′G′B′) channels in 0...1, row-major.
struct RGBImage: Equatable {
    var width: Int
    var height: Int
    var r: [Float], g: [Float], b: [Float]
}

/// Transfer functions, Y′CbCr and chroma subsampling for Lesson 13.
enum ColourDSP {

    // MARK: - Transfer functions (gamma)

    enum Transfer: String, CaseIterable, Identifiable {
        case linear = "Linear (no gamma)", sRGB = "sRGB", gamma22 = "Power 2.2", bt1886 = "BT.1886 (2.4)"
        var id: String { rawValue }

        /// Linear light → stored value (the OETF / inverse EOTF).
        func encode(_ l: Double) -> Double {
            let l = min(max(l, 0), 1)
            switch self {
            case .linear:  return l
            case .sRGB:    return l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055
            case .gamma22: return pow(l, 1 / 2.2)
            case .bt1886:  return pow(l, 1 / 2.4)
            }
        }

        /// Stored value → linear light (what the display does).
        func decode(_ v: Double) -> Double {
            let v = min(max(v, 0), 1)
            switch self {
            case .linear:  return v
            case .sRGB:    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            case .gamma22: return pow(v, 2.2)
            case .bt1886:  return pow(v, 2.4)
            }
        }
    }

    static func quantize(_ v: Double, bits: Int) -> Double {
        let levels = Double((1 << bits) - 1)
        return (min(max(v, 0), 1) * levels).rounded() / levels
    }

    /// A horizontal ramp of linear light 0→1, stored at `bits` through `transfer`, returned as the
    /// linear light the display would emit for each of `count` positions.
    static func storedRamp(count: Int, bits: Int, transfer: Transfer) -> [Double] {
        (0..<count).map { i in
            let l = Double(i) / Double(max(count - 1, 1))
            return transfer.decode(quantize(transfer.encode(l), bits: bits))
        }
    }

    /// How many distinct code values cover linear light below `limit` (e.g. 0.1 = darkest 10%).
    static func codesBelow(_ limit: Double, bits: Int, transfer: Transfer) -> Int {
        Int((transfer.encode(limit) * Double((1 << bits) - 1)).rounded(.down)) + 1
    }

    // MARK: - Y′CbCr (BT.601 full range, as JPEG uses)

    static func toYCbCr(r: Float, g: Float, b: Float) -> (y: Float, cb: Float, cr: Float) {
        (0.299 * r + 0.587 * g + 0.114 * b,
         -0.168736 * r - 0.331264 * g + 0.5 * b,
         0.5 * r - 0.418688 * g - 0.081312 * b)
    }

    static func toRGB(y: Float, cb: Float, cr: Float) -> (r: Float, g: Float, b: Float) {
        (y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb)
    }

    enum Subsampling: String, CaseIterable, Identifiable {
        case s444 = "4:4:4", s422 = "4:2:2", s420 = "4:2:0"
        var id: String { rawValue }
        /// Chroma block size (horizontal, vertical).
        var block: (Int, Int) { switch self { case .s444: (1, 1); case .s422: (2, 1); case .s420: (2, 2) } }
        /// Samples stored per pixel: 1 luma + 2 chroma divided by the block area.
        var samplesPerPixel: Double { 1 + 2 / Double(block.0 * block.1) }
    }

    enum Channel: String, CaseIterable, Identifiable {
        case result = "Result", luma = "Y′ (luma)", cb = "Cb (blue − luma)", cr = "Cr (red − luma)"
        var id: String { rawValue }
    }

    /// Converts to Y′CbCr, averages chroma over each block, replicates it back, converts to R′G′B′.
    static func subsample(_ img: RGBImage, _ mode: Subsampling) -> (image: RGBImage, y: [Float], cb: [Float], cr: [Float]) {
        let n = img.width * img.height
        var y = [Float](repeating: 0, count: n), cb = y, cr = y
        for i in 0..<n { (y[i], cb[i], cr[i]) = toYCbCr(r: img.r[i], g: img.g[i], b: img.b[i]) }
        let (bw, bh) = mode.block
        if bw * bh > 1 {
            for by in stride(from: 0, to: img.height, by: bh) { for bx in stride(from: 0, to: img.width, by: bw) {
                var sb: Float = 0, sr: Float = 0, k: Float = 0
                var idx: [Int] = []
                for dy in 0..<bh where by + dy < img.height { for dx in 0..<bw where bx + dx < img.width {
                    let i = (by + dy) * img.width + bx + dx
                    sb += cb[i]; sr += cr[i]; k += 1; idx.append(i)
                } }
                for i in idx { cb[i] = sb / k; cr[i] = sr / k }
            } }
        }
        var out = RGBImage(width: img.width, height: img.height, r: y, g: y, b: y)
        for i in 0..<n {
            let c = toRGB(y: y[i], cb: cb[i], cr: cr[i])
            out.r[i] = min(max(c.r, 0), 1); out.g[i] = min(max(c.g, 0), 1); out.b[i] = min(max(c.b, 0), 1)
        }
        return (out, y, cb, cr)
    }

    /// Visualises one channel: luma as gray; Cb/Cr as colour around mid-gray, so you can see what they carry.
    static func channelView(_ channel: Channel, result: RGBImage, y: [Float], cb: [Float], cr: [Float]) -> RGBImage {
        switch channel {
        case .result: return result
        case .luma:   return RGBImage(width: result.width, height: result.height, r: y, g: y, b: y)
        case .cb, .cr:
            var out = result
            for i in y.indices {
                let c = channel == .cb ? toRGB(y: 0.5, cb: cb[i], cr: 0) : toRGB(y: 0.5, cb: 0, cr: cr[i])
                out.r[i] = min(max(c.r, 0), 1); out.g[i] = min(max(c.g, 0), 1); out.b[i] = min(max(c.b, 0), 1)
            }
            return out
        }
    }

    static func psnr(_ a: RGBImage, _ b: RGBImage) -> Double {
        var se = 0.0
        for i in a.r.indices {
            let dr: Float = a.r[i] - b.r[i], dg: Float = a.g[i] - b.g[i], db: Float = a.b[i] - b.b[i]
            se += Double(dr * dr + dg * dg + db * db)
        }
        let mse = se / Double(a.r.count * 3)
        return mse == 0 ? .infinity : 10 * log10(1 / mse)
    }

    // MARK: - Sources

    /// Colour test card: colour bars, a hue sweep, red text on blue, and fine coloured stripes —
    /// the details chroma subsampling hurts most.
    static func colourCard(size: Int = 320) -> RGBImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let s = CGFloat(size)
        func fill(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ rect: CGRect) {
            ctx.setFillColor(CGColor(colorSpace: cs, components: [r, g, b, 1])!); ctx.fill(rect)
        }
        // Top third: 75% colour bars (white, yellow, cyan, green, magenta, red, blue). CG's origin is bottom-left.
        let bars: [(CGFloat, CGFloat, CGFloat)] = [(0.75, 0.75, 0.75), (0.75, 0.75, 0), (0, 0.75, 0.75), (0, 0.75, 0), (0.75, 0, 0.75), (0.75, 0, 0), (0, 0, 0.75)]
        for (i, c) in bars.enumerated() {
            fill(c.0, c.1, c.2, CGRect(x: CGFloat(i) * s / 7, y: s * 0.68, width: s / 7 + 1, height: s * 0.32))
        }
        // Hue sweep.
        for x in 0..<size {
            let c = NSColor(hue: CGFloat(x) / s, saturation: 0.85, brightness: 0.9, alpha: 1).usingColorSpace(.sRGB)!
            fill(c.redComponent, c.greenComponent, c.blueComponent, CGRect(x: CGFloat(x), y: s * 0.5, width: 1, height: s * 0.18))
        }
        // Bottom-left: red text on blue (classic chroma-bleed case).
        fill(0.05, 0.1, 0.65, CGRect(x: 0, y: 0, width: s * 0.55, height: s * 0.5))
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        // Placed inside the centre crop so "Zoom 2×" shows it.
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: s * 0.06), .foregroundColor: NSColor(srgbRed: 0.95, green: 0.1, blue: 0.1, alpha: 1)]
        NSAttributedString(string: "CHROMA", attributes: attrs).draw(at: CGPoint(x: s * 0.27, y: s * 0.38))
        NSAttributedString(string: "4:2:0", attributes: attrs).draw(at: CGPoint(x: s * 0.27, y: s * 0.28))
        NSGraphicsContext.restoreGraphicsState()
        // Bottom-right: 1-pixel red/green stripes over a gray patch; equal-luma colour detail.
        for x in Int(s * 0.55)..<size {
            let even = x % 2 == 0
            fill(even ? 0.8 : 0.15, even ? 0.2 : 0.55, 0.2, CGRect(x: CGFloat(x), y: s * 0.25, width: 1, height: s * 0.25))
        }
        // A smooth skin-tone patch: subsampling is invisible on areas like this.
        fill(0.86, 0.62, 0.5, CGRect(x: s * 0.55, y: 0, width: s * 0.45, height: s * 0.25))
        return RGBImage(cgImage: ctx.makeImage()!, maxSide: size)!
    }

    static func load(url: URL, maxSide: Int = 360) -> RGBImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return RGBImage(cgImage: cg, maxSide: maxSide)
    }
}

extension RGBImage {
    init?(cgImage: CGImage, maxSide: Int) {
        let k = min(1, Double(maxSide) / Double(max(cgImage.width, cgImage.height)))
        let w = max(Int(Double(cgImage.width) * k), 8), h = max(Int(Double(cgImage.height) * k), 8)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        let n = w * h
        self.init(width: w, height: h,
                  r: (0..<n).map { Float(bytes[$0 * 4]) / 255 },
                  g: (0..<n).map { Float(bytes[$0 * 4 + 1]) / 255 },
                  b: (0..<n).map { Float(bytes[$0 * 4 + 2]) / 255 })
    }

    var cgImage: CGImage? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            bytes[i * 4] = UInt8(min(max(r[i], 0), 1) * 255)
            bytes[i * 4 + 1] = UInt8(min(max(g[i], 0), 1) * 255)
            bytes[i * 4 + 2] = UInt8(min(max(b[i], 0), 1) * 255)
        }
        return bytes.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
    }

    /// Centre crop at half size, for zooming in on subsampling artefacts.
    func centreCrop() -> RGBImage {
        let w = width / 2, h = height / 2, x0 = width / 4, y0 = height / 4
        var out = RGBImage(width: w, height: h, r: [], g: [], b: [])
        for y in 0..<h { for x in 0..<w {
            let i = (y0 + y) * width + x0 + x
            out.r.append(r[i]); out.g.append(g[i]); out.b.append(b[i])
        } }
        return out
    }
}

// MARK: - White balance

/// Light colour vs. temperature, camera gains, and automatic estimates. All maths is in linear light.
enum WhiteBalance {
    struct RGB: Equatable { var r: Double, g: Double, b: Double }

    static let reference = 6500.0     // the temperature that renders neutral with unity gains

    /// CIE 1931 xy of a black body at `kelvin` (Kim et al. cubic fit to the Planckian locus, 1667–25000 K).
    static func planckianXY(_ kelvin: Double) -> (x: Double, y: Double) {
        let t = min(max(kelvin, 1667), 25000), t2 = t * t, t3 = t2 * t
        let x = t <= 4000
            ? -0.2661239e9 / t3 - 0.2343589e6 / t2 + 0.8776956e3 / t + 0.179910
            : -3.0258469e9 / t3 + 2.1070379e6 / t2 + 0.2226347e3 / t + 0.240390
        let x2 = x * x, x3 = x2 * x
        let y: Double
        if t <= 2222 { y = -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683 }
        else if t <= 4000 { y = -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867 }
        else { y = 3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483 }
        return (x, y)
    }

    /// Tint (−100 green … +100 magenta, as in Lightroom/Premiere) → distance from the locus in CIE 1960 uv.
    /// +100 is Duv −0.02 (below the locus, magenta); −100 is Duv +0.02 (above, green).
    static func duv(tint: Double) -> Double { -tint / 100 * 0.02 }

    /// xy of light at `kelvin`, moved off the Planckian locus along its normal by the tint.
    static func lightXY(_ kelvin: Double, tint: Double) -> (x: Double, y: Double) {
        func uv(_ k: Double) -> (u: Double, v: Double) {
            let (x, y) = planckianXY(k), d = -2 * x + 12 * y + 3
            return (4 * x / d, 6 * y / d)
        }
        let p = uv(kelvin)
        guard tint != 0 else { return planckianXY(kelvin) }
        let a = uv(kelvin - 10), b = uv(kelvin + 10)
        var nu = -(b.v - a.v), nv = b.u - a.u                 // normal to the locus
        let len = (nu * nu + nv * nv).squareRoot()
        nu /= len; nv /= len
        if nv < 0 { nu = -nu; nv = -nv }                      // positive Duv points towards green (higher v)
        let d = duv(tint: tint), u = p.u + d * nu, v = p.v + d * nv, den = 2 * u - 8 * v + 4
        return (3 * u / den, 2 * v / den)
    }

    private static func rawRGB(_ xy: (x: Double, y: Double)) -> RGB {
        let X = xy.x / xy.y, Z = (1 - xy.x - xy.y) / xy.y          // Y = 1
        return RGB(r: max(3.2406 * X - 1.5372 - 0.4986 * Z, 0.001),
                   g: max(-0.9689 * X + 1.8758 + 0.0415 * Z, 0.001),
                   b: max(0.0557 * X - 0.2040 + 1.0570 * Z, 0.001))
    }
    private static let referenceRGB = rawRGB(planckianXY(reference))

    /// Linear-sRGB colour of the light at `kelvin` and `tint`, scaled so 6,500 K / tint 0 is (1, 1, 1) and green is 1.
    static func illuminant(_ kelvin: Double, tint: Double = 0) -> RGB {
        let c = rawRGB(lightXY(kelvin, tint: tint)), ref = referenceRGB
        let r = c.r / ref.r, g = c.g / ref.g, b = c.b / ref.b
        return RGB(r: r / g, g: 1, b: b / g)
    }

    /// Camera white-balance gains for an assumed light: divide it out, keeping green at 1 (as cameras do).
    static func gains(forKelvin kelvin: Double, tint: Double = 0) -> RGB {
        let l = illuminant(kelvin, tint: tint)
        return RGB(r: 1 / l.r, g: 1, b: 1 / l.b)
    }

    /// Gains that make a measured colour neutral.
    static func gains(neutral c: RGB) -> RGB {
        RGB(r: c.g / max(c.r, 1e-6), g: 1, b: c.g / max(c.b, 1e-6))
    }

    /// Nearest temperature and tint to a measured light colour (grid search on log chromaticity ratios).
    static func estimate(_ c: RGB) -> (kelvin: Double, tint: Double) {
        let tr = log(c.r / max(c.g, 1e-9)), tb = log(c.b / max(c.g, 1e-9))
        func err(_ k: Double, _ t: Double) -> Double {
            let l = illuminant(k, tint: t)
            return pow(log(l.r) - tr, 2) + pow(log(l.b) - tb, 2)
        }
        var best = (kelvin: reference, tint: 0.0), bestErr = Double.infinity
        for k in stride(from: 2000.0, through: 10000, by: 100) {
            for t in stride(from: -100.0, through: 100, by: 5) where err(k, t) < bestErr { bestErr = err(k, t); best = (k, t) }
        }
        // Refine around the coarse best.
        for k in stride(from: best.kelvin - 100, through: best.kelvin + 100, by: 10) {
            for t in stride(from: best.tint - 5, through: best.tint + 5, by: 1) where err(k, t) < bestErr { bestErr = err(k, t); best = (k, t) }
        }
        return best
    }

    static func estimateKelvin(_ c: RGB) -> Double { estimate(c).kelvin }

    /// The scene as the sensor records it: linear reflectance × light. Input and output are R′G′B′ (sRGB-encoded).
    /// Exposure is set so the light's strongest channel is 1 (like auto-exposure), so white never clips.
    static func capture(_ img: RGBImage, lightKelvin: Double, tint: Double = 0) -> RGBImage {
        let l = illuminant(lightKelvin, tint: tint), m = max(l.r, l.g, l.b)
        return apply(img, multiply: RGB(r: l.r / m, g: l.g / m, b: l.b / m))
    }

    /// Applies camera gains in linear light, then re-encodes (values above 1 clip, as on a real camera).
    static func correct(_ captured: RGBImage, gains: RGB) -> RGBImage {
        apply(captured, multiply: gains)
    }

    /// Gray-world estimate: the average colour of the scene is assumed to be neutral.
    static func grayWorld(_ captured: RGBImage) -> RGB {
        var s = RGB(r: 0, g: 0, b: 0)
        let t = ColourDSP.Transfer.sRGB
        for i in captured.r.indices {
            s.r += t.decode(Double(captured.r[i])); s.g += t.decode(Double(captured.g[i])); s.b += t.decode(Double(captured.b[i]))
        }
        return s
    }

    /// Mean linear colour of a small square around (x, y): the eyedropper.
    static func sample(_ img: RGBImage, x: Int, y: Int, radius: Int = 2) -> RGB {
        var s = RGB(r: 0, g: 0, b: 0)
        let t = ColourDSP.Transfer.sRGB
        for yy in max(y - radius, 0)...min(y + radius, img.height - 1) {
            for xx in max(x - radius, 0)...min(x + radius, img.width - 1) {
                let i = yy * img.width + xx
                s.r += t.decode(Double(img.r[i])); s.g += t.decode(Double(img.g[i])); s.b += t.decode(Double(img.b[i]))
            }
        }
        return s
    }

    private static func apply(_ img: RGBImage, multiply m: RGB) -> RGBImage {
        let t = ColourDSP.Transfer.sRGB
        var out = img
        for i in img.r.indices {
            out.r[i] = Float(t.encode(t.decode(Double(img.r[i])) * m.r))
            out.g[i] = Float(t.encode(t.decode(Double(img.g[i])) * m.g))
            out.b[i] = Float(t.encode(t.decode(Double(img.b[i])) * m.b))
        }
        return out
    }

    /// A 6×4 colour-checker chart (published sRGB approximations of the standard patches), bottom row neutral.
    static func checkerChart(width: Int = 360) -> RGBImage {
        let hex: [UInt32] = [
            0x735244, 0xC29682, 0x627A9D, 0x576C43, 0x8580B1, 0x67BDAA,
            0xD67E2C, 0x505BA6, 0xC15A63, 0x5E3C6C, 0x9DBC40, 0xE0A32E,
            0x383D96, 0x469449, 0xAF363C, 0xE7C71F, 0xBB5695, 0x0885A1,
            0xF3F3F2, 0xC8C8C8, 0xA0A0A0, 0x7A7A79, 0x555555, 0x343434]
        let cell = width / 6, gap = max(cell / 12, 2), height = cell * 4
        let n = width * height
        var img = RGBImage(width: width, height: height,
                           r: [Float](repeating: 0.1, count: n), g: [Float](repeating: 0.1, count: n), b: [Float](repeating: 0.1, count: n))
        for (k, v) in hex.enumerated() {
            let cx = (k % 6) * cell, cy = (k / 6) * cell
            let r = Float((v >> 16) & 0xFF) / 255, g = Float((v >> 8) & 0xFF) / 255, b = Float(v & 0xFF) / 255
            for y in (cy + gap)..<(cy + cell - gap) { for x in (cx + gap)..<min(cx + cell - gap, width) {
                let i = y * width + x
                img.r[i] = r; img.g[i] = g; img.b[i] = b
            } }
        }
        return img
    }

    /// Centre of the "neutral 6.5" patch (bottom row, third from left) — handy for tests and the readout.
    static func grayPatchCentre(width: Int = 360) -> (x: Int, y: Int) {
        let cell = width / 6
        return (2 * cell + cell / 2, 3 * cell + cell / 2)
    }
}

// MARK: - Gamuts

/// The CIE 1931 chromaticity diagram, the spectral locus, and RGB gamut triangles.
enum Gamut {
    struct XY: Equatable { var x: Double, y: Double }
    struct Space: Identifiable, Equatable {
        let name: String, red: XY, green: XY, blue: XY
        var id: String { name }
        var corners: [XY] { [red, green, blue] }
    }

    static let rec709 = Space(name: "Rec.709 / sRGB", red: XY(x: 0.640, y: 0.330), green: XY(x: 0.300, y: 0.600), blue: XY(x: 0.150, y: 0.060))
    static let p3 = Space(name: "DCI-P3", red: XY(x: 0.680, y: 0.320), green: XY(x: 0.265, y: 0.690), blue: XY(x: 0.150, y: 0.060))
    static let rec2020 = Space(name: "Rec.2020", red: XY(x: 0.708, y: 0.292), green: XY(x: 0.170, y: 0.797), blue: XY(x: 0.131, y: 0.046))
    static let spaces = [rec709, p3, rec2020]
    static let d65 = XY(x: 0.3127, y: 0.3290)

    /// CIE 1931 2° chromaticities of monochromatic light, 380–700 nm in 5 nm steps (x, y pairs).
    private static let spectralTable: [Double] = [
        0.1741, 0.0050, 0.1740, 0.0050, 0.1738, 0.0049, 0.1736, 0.0049, 0.1733, 0.0048, 0.1730, 0.0048, 0.1726, 0.0048, 0.1721, 0.0048,
        0.1714, 0.0051, 0.1703, 0.0058, 0.1689, 0.0069, 0.1669, 0.0086, 0.1644, 0.0109, 0.1611, 0.0138, 0.1566, 0.0177, 0.1510, 0.0227,
        0.1440, 0.0297, 0.1355, 0.0399, 0.1241, 0.0578, 0.1096, 0.0868, 0.0913, 0.1327, 0.0687, 0.2007, 0.0454, 0.2950, 0.0235, 0.4127,
        0.0082, 0.5384, 0.0039, 0.6548, 0.0139, 0.7502, 0.0389, 0.8120, 0.0743, 0.8338, 0.1142, 0.8262, 0.1547, 0.8059, 0.1929, 0.7816,
        0.2296, 0.7543, 0.2658, 0.7243, 0.3016, 0.6923, 0.3373, 0.6589, 0.3731, 0.6245, 0.4087, 0.5896, 0.4441, 0.5547, 0.4788, 0.5202,
        0.5125, 0.4866, 0.5448, 0.4544, 0.5752, 0.4242, 0.6029, 0.3965, 0.6270, 0.3725, 0.6482, 0.3514, 0.6658, 0.3340, 0.6801, 0.3197,
        0.6915, 0.3083, 0.7006, 0.2993, 0.7079, 0.2920, 0.7140, 0.2859, 0.7190, 0.2809, 0.7230, 0.2770, 0.7260, 0.2740, 0.7283, 0.2717,
        0.7300, 0.2700, 0.7311, 0.2689, 0.7320, 0.2680, 0.7327, 0.2673, 0.7334, 0.2666, 0.7340, 0.2660, 0.7344, 0.2656, 0.7346, 0.2654,
        0.7347, 0.2653]

    /// Chromaticity of pure light at one wavelength — a point on the curved edge of the diagram (linear interpolation).
    static func spectral(_ nm: Double) -> XY {
        let f = (min(max(nm, 380), 700) - 380) / 5
        let i = min(Int(f), 63), t = f - Double(i)
        let ax = spectralTable[2 * i], ay = spectralTable[2 * i + 1], bx = spectralTable[2 * i + 2], by = spectralTable[2 * i + 3]
        return XY(x: ax + (bx - ax) * t, y: ay + (by - ay) * t)
    }

    /// The spectral locus from 380 to 700 nm; the straight edge back to 380 nm is the line of purples.
    static let locus: [XY] = stride(from: 0, to: spectralTable.count, by: 2).map { XY(x: spectralTable[$0], y: spectralTable[$0 + 1]) }

    /// Points on an edge or corner count as inside (a primary is in its own gamut).
    static func contains(_ s: Space, _ p: XY) -> Bool { inPolygon(p, s.corners) || nearEdge(p, s.corners) }
    static func isVisible(_ p: XY) -> Bool { inPolygon(p, locus) || nearEdge(p, locus) }

    private static func nearEdge(_ p: XY, _ poly: [XY], tolerance: Double = 1e-4) -> Bool {
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[j], b = poly[i]
            let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0), 1)
            let ex = a.x + t * dx - p.x, ey = a.y + t * dy - p.y
            if ex * ex + ey * ey <= tolerance * tolerance { return true }
            j = i
        }
        return false
    }

    /// Even-odd ray-casting point-in-polygon test.
    static func inPolygon(_ p: XY, _ poly: [XY]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// A displayable approximation of a chromaticity: XYZ (Y = 1) → linear sRGB, out-of-range negatives
    /// clipped to 0, scaled so the largest channel is 1, then sRGB-encoded. Colours outside sRGB come out
    /// as the nearest colour this screen can show, so the diagram's edges are always desaturated.
    static func displayRGB(_ p: XY) -> (r: Double, g: Double, b: Double) {
        let X = p.x / p.y, Z = (1 - p.x - p.y) / p.y
        var r = 3.2406 * X - 1.5372 - 0.4986 * Z
        var g = -0.9689 * X + 1.8758 + 0.0415 * Z
        var b = 0.0557 * X - 0.2040 + 1.0570 * Z
        r = max(r, 0); g = max(g, 0); b = max(b, 0)
        let m = max(r, g, b, 1e-9)
        let t = ColourDSP.Transfer.sRGB
        return (t.encode(r / m), t.encode(g / m), t.encode(b / m))
    }

    /// The diagram's colour fill over x ∈ 0…0.8, y ∈ 0…0.9 (outside the locus is transparent).
    static func diagramImage(width: Int = 320) -> CGImage? {
        let height = Int(Double(width) * 0.9 / 0.8)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height { for col in 0..<width {
            let p = XY(x: (Double(col) + 0.5) / Double(width) * 0.8, y: (1 - (Double(row) + 0.5) / Double(height)) * 0.9)
            guard isVisible(p) else { continue }
            let c = displayRGB(p), o = (row * width + col) * 4
            bytes[o] = UInt8(c.r * 255); bytes[o + 1] = UInt8(c.g * 255); bytes[o + 2] = UInt8(c.b * 255); bytes[o + 3] = 255
        } }
        return bytes.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
}
