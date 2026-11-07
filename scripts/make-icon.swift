// Draws the app icon (blue rounded square, white location arrow) into the asset catalog: swift scripts/make-icon.swift
import AppKit

let dir = "GPSChanger/Assets.xcassets/AppIcon.appiconset"
func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: 824/1024 body with margin.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.62, blue: 1.0, alpha: 1), NSColor(red: 0.04, green: 0.33, blue: 0.86, alpha: 1)])!
        .draw(in: path, angle: -90)
    // Location arrow (pointing up-right), like Maps' location button.
    let c = NSPoint(x: s / 2, y: s / 2), r = body.width * 0.30
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: c.x + r, y: c.y + r))
    arrow.line(to: NSPoint(x: c.x - r * 0.95, y: c.y + r * 0.05))
    arrow.line(to: NSPoint(x: c.x - r * 0.02, y: c.y + r * 0.02))
    arrow.line(to: NSPoint(x: c.x - r * 0.05, y: c.y - r * 0.95))
    arrow.close()
    arrow.lineJoinStyle = .round
    arrow.lineWidth = s * 0.02
    NSColor.white.setFill(); NSColor.white.setStroke()
    arrow.fill(); arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let file = "icon_\(pt)x\(pt)@\(scale)x.png"
        try! draw(pt * scale).write(to: URL(fileURLWithPath: "\(dir)/\(file)"))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": file])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(dir)/Contents.json"))
print("icons written")
