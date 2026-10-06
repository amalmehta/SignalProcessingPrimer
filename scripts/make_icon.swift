// Renders the app icon (a waveform turning into pixels) at every macOS size.
// Usage: swift scripts/make_icon.swift "Signal Processing Primer/Resources/Assets.xcassets/AppIcon.appiconset"
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1, rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(srgbRed: 0.05, green: 0.21, blue: 0.42, alpha: 1),
               ending: NSColor(srgbRed: 0.16, green: 0.47, blue: 0.84, alpha: 1))!.draw(in: bg, angle: 90)
    // Continuous wave on the left half…
    let wave = NSBezierPath(); wave.lineWidth = s * 0.035; wave.lineCapStyle = .round
    let midY = s / 2, amp = s * 0.17, x0 = rect.minX + s * 0.08, x1 = s * 0.52
    for i in 0...100 {
        let x = x0 + (x1 - x0) * CGFloat(i) / 100
        let y = midY + amp * sin((x - x0) / (s * 0.42) * 2 * .pi * 1.25)
        i == 0 ? wave.move(to: NSPoint(x: x, y: y)) : wave.line(to: NSPoint(x: x, y: y))
    }
    NSColor.white.setStroke(); wave.stroke()
    // …becoming sampled bars on the right.
    NSColor(srgbRed: 0.92, green: 0.41, blue: 0.20, alpha: 1).setFill()
    for k in 0..<5 {
        let x = s * 0.56 + CGFloat(k) * s * 0.065
        let y = midY + amp * sin((x - x0) / (s * 0.42) * 2 * .pi * 1.25)
        let top = max(y, midY), bottom = min(y, midY)
        NSBezierPath(roundedRect: NSRect(x: x, y: bottom, width: s * 0.04, height: max(top - bottom, s * 0.02)),
                     xRadius: s * 0.01, yRadius: s * 0.01).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! render(base * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let json = try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]],
                                       options: [.prettyPrinted, .sortedKeys])
try! json.write(to: out.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon images")
