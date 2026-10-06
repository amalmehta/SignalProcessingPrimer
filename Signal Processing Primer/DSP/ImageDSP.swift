import AppKit
import CoreGraphics
import Foundation

/// A grayscale image as a 2-D signal: row-major luminance in 0...1.
struct GrayImage: Equatable {
    var width: Int
    var height: Int
    var pixels: [Float]

    subscript(x: Int, y: Int) -> Float {
        pixels[min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)]  // clamp-to-edge
    }
}

enum ImageDSP {

    // MARK: - Sources

    /// Procedural test card: gradients, fine stripes, a checkerboard, circles and text —
    /// every feature a filter demo needs, with no licensing questions.
    static func testCard(size: Int = 320) -> GrayImage {
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let s = CGFloat(size)
        // Sky-like vertical gradient.
        let grad = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 0.85, alpha: 1), CGColor(gray: 0.35, alpha: 1)] as CFArray, locations: nil)!
        ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: s), options: [])
        // Checkerboard (sharp edges).
        let cell = s / 16
        for i in 0..<4 { for j in 0..<4 where (i + j) % 2 == 0 {
            ctx.setFillColor(gray: 0.05, alpha: 1)
            ctx.fill(CGRect(x: s * 0.06 + CGFloat(i) * cell, y: s * 0.06 + CGFloat(j) * cell, width: cell, height: cell))
        } }
        // Fine stripes (high frequency — shows moiré and blur).
        for i in 0..<20 {
            ctx.setFillColor(gray: i % 2 == 0 ? 1 : 0, alpha: 1)
            ctx.fill(CGRect(x: s * 0.55 + CGFloat(i) * s * 0.02, y: s * 0.06, width: s * 0.02, height: s * 0.25))
        }
        // Circles (curved edges at every angle).
        ctx.setFillColor(gray: 0.95, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: s * 0.1, y: s * 0.45, width: s * 0.35, height: s * 0.35))
        ctx.setStrokeColor(gray: 0.1, alpha: 1); ctx.setLineWidth(s * 0.015)
        ctx.strokeEllipse(in: CGRect(x: s * 0.55, y: s * 0.45, width: s * 0.33, height: s * 0.33))
        // Text (fine detail).
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: s * 0.09), .foregroundColor: NSColor.white]
        NSAttributedString(string: "SIGNAL", attributes: attrs).draw(at: CGPoint(x: s * 0.2, y: s * 0.86))
        NSGraphicsContext.restoreGraphicsState()
        return GrayImage(cgImage: ctx.makeImage()!, maxSide: size)!
    }

    static func load(url: URL, maxSide: Int = 360) -> GrayImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return GrayImage(cgImage: cg, maxSide: maxSide)
    }

    // MARK: - 2-D convolution

    enum Kernel: String, CaseIterable, Identifiable {
        case identity = "Original", boxBlur = "Box blur", gaussian = "Gaussian blur", sharpen = "Sharpen",
             sobelX = "Edges (Sobel X)", edgeMagnitude = "Edges (Sobel magnitude)", emboss = "Emboss"
        var id: String { rawValue }

        func matrix(strength: Int) -> [[Float]] {
            switch self {
            case .identity: return [[1]]
            case .boxBlur:
                let n = 2 * strength + 1
                return Array(repeating: Array(repeating: 1 / Float(n * n), count: n), count: n)
            case .gaussian:
                let g = DSP.gaussianKernel(4 * strength + 1)
                return g.map { a in g.map { a * $0 } }
            case .sharpen:
                let a = Float(strength) * 0.5
                return [[0, -a, 0], [-a, 1 + 4 * a, -a], [0, -a, 0]]
            case .sobelX, .edgeMagnitude: return [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
            case .emboss: return [[-2, -1, 0], [-1, 1, 1], [0, 1, 2]]
            }
        }
    }

    static func convolve(_ img: GrayImage, kernel k: [[Float]]) -> GrayImage {
        let kh = k.count, kw = k[0].count, oy = kh / 2, ox = kw / 2
        var out = [Float](repeating: 0, count: img.pixels.count)
        for y in 0..<img.height { for x in 0..<img.width {
            var acc: Float = 0
            for j in 0..<kh { for i in 0..<kw { acc += k[j][i] * img[x + i - ox, y + j - oy] } }
            out[y * img.width + x] = acc
        } }
        return GrayImage(width: img.width, height: img.height, pixels: out)
    }

    static func apply(_ kernel: Kernel, strength: Int, to img: GrayImage) -> GrayImage {
        switch kernel {
        case .identity: return img
        case .sobelX:
            var r = convolve(img, kernel: kernel.matrix(strength: strength))
            r.pixels = r.pixels.map { min(max($0 * 0.5 + 0.5, 0), 1) }   // show signed edges around mid-gray
            return r
        case .edgeMagnitude:
            let gx = convolve(img, kernel: kernel.matrix(strength: strength))
            let ky = [[Float(-1), -2, -1], [0, 0, 0], [1, 2, 1]]
            let gy = convolve(img, kernel: ky)
            return GrayImage(width: img.width, height: img.height,
                             pixels: zip(gx.pixels, gy.pixels).map { min(sqrt($0 * $0 + $1 * $1), 1) })
        case .emboss:
            var r = convolve(img, kernel: kernel.matrix(strength: strength))
            r.pixels = r.pixels.map { min(max($0 * 0.5, 0), 1) }
            return r
        default:
            var r = convolve(img, kernel: kernel.matrix(strength: strength))
            r.pixels = r.pixels.map { min(max($0, 0), 1) }
            return r
        }
    }

    // MARK: - DCT / JPEG

    /// Standard JPEG luminance quantization table (ITU T.81 Annex K).
    static let jpegLuma: [Float] = [
        16, 11, 10, 16, 24, 40, 51, 61,   12, 12, 14, 19, 26, 58, 60, 55,
        14, 13, 16, 24, 40, 57, 69, 56,   14, 17, 22, 29, 51, 87, 80, 62,
        18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
        49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99]

    private static let cosTable: [Float] = (0..<8).flatMap { x in
        (0..<8).map { u in Float(cos(Double(2 * x + 1) * Double(u) * .pi / 16)) }
    }
    private static func c(_ u: Int) -> Float { u == 0 ? Float(1 / sqrt(2.0)) : 1 }

    /// 8×8 DCT-II (orthonormal JPEG scaling). Input/output row-major, 64 values.
    static func dct8x8(_ block: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: 64)
        for v in 0..<8 { for u in 0..<8 {
            var s: Float = 0
            for y in 0..<8 { for x in 0..<8 { s += block[y * 8 + x] * cosTable[x * 8 + u] * cosTable[y * 8 + v] } }
            out[v * 8 + u] = 0.25 * c(u) * c(v) * s
        } }
        return out
    }

    static func idct8x8(_ coeffs: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: 64)
        for y in 0..<8 { for x in 0..<8 {
            var s: Float = 0
            for v in 0..<8 { for u in 0..<8 { s += c(u) * c(v) * coeffs[v * 8 + u] * cosTable[x * 8 + u] * cosTable[y * 8 + v] } }
            out[y * 8 + x] = 0.25 * s
        } }
        return out
    }

    /// libjpeg's quality → table scaling (quality 1...100).
    static func quantTable(quality: Int) -> [Float] {
        let q = Float(min(max(quality, 1), 100))
        let scale = q < 50 ? 5000 / q : 200 - 2 * q
        return jpegLuma.map { max(1, (($0 * scale + 50) / 100).rounded(.down)) }
    }

    struct JPEGResult { var image: GrayImage; var zeroFraction: Double; var psnr: Double }

    /// Runs the lossy heart of JPEG: blockwise DCT → quantize → dequantize → inverse DCT.
    static func jpegRoundTrip(_ img: GrayImage, quality: Int) -> JPEGResult {
        let table = quantTable(quality: quality)
        var out = img.pixels, zeros = 0, total = 0
        for by in stride(from: 0, to: img.height, by: 8) { for bx in stride(from: 0, to: img.width, by: 8) {
            var block = [Float](repeating: 0, count: 64)
            for y in 0..<8 { for x in 0..<8 { block[y * 8 + x] = img[bx + x, by + y] * 255 - 128 } }
            let coeffs = dct8x8(block)
            let quantized = zip(coeffs, table).map { ($0 / $1).rounded() }
            zeros += quantized.filter { $0 == 0 }.count; total += 64
            let rec = idct8x8(zip(quantized, table).map { $0 * $1 })
            for y in 0..<8 { for x in 0..<8 where bx + x < img.width && by + y < img.height {
                out[(by + y) * img.width + bx + x] = min(max((rec[y * 8 + x] + 128) / 255, 0), 1)
            } }
        } }
        let mse = zip(img.pixels, out).reduce(0.0) { $0 + Double(($1.0 - $1.1) * ($1.0 - $1.1)) } / Double(out.count)
        return JPEGResult(image: GrayImage(width: img.width, height: img.height, pixels: out),
                          zeroFraction: Double(zeros) / Double(total),
                          psnr: mse == 0 ? .infinity : 10 * log10(1 / mse))
    }

    // MARK: - Tone

    /// Display encoding: linear light → gamma-encoded value.
    static func gammaEncode(_ linear: Double, gamma: Double) -> Double { pow(max(linear, 0), 1 / gamma) }
}

extension GrayImage {
    init?(cgImage: CGImage, maxSide: Int) {
        let scale = min(1, Double(maxSide) / Double(max(cgImage.width, cgImage.height)))
        let w = max(Int(Double(cgImage.width) * scale), 8), h = max(Int(Double(cgImage.height) * scale), 8)
        var bytes = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        self.init(width: w, height: h, pixels: bytes.map { Float($0) / 255 })
    }

    var cgImage: CGImage? {
        var bytes = pixels.map { UInt8(min(max($0, 0), 1) * 255) }
        return bytes.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
    }
}
