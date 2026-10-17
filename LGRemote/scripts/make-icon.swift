// Renders the app icon into an .iconset folder: swift make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func gray(_ w: CGFloat) -> NSColor { NSColor(calibratedWhite: w, alpha: 1) }

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // Background tile (macOS icon grid: 824pt square inset by 100).
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(calibratedRed: 0.95, green: 0.2, blue: 0.38, alpha: 1),
               ending: NSColor(calibratedRed: 0.5, green: 0.04, blue: 0.24, alpha: 1))!.draw(in: tile, angle: -90)

    // Remote body with a soft shadow.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    let body = NSBezierPath(roundedRect: NSRect(x: 372, y: 160, width: 280, height: 704), xRadius: 120, yRadius: 120)
    gray(0.1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: gray(0.24), ending: gray(0.08))!.draw(in: body, angle: -90)

    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
    }
    circle(512, 780, 28, NSColor(calibratedRed: 0.9, green: 0.18, blue: 0.22, alpha: 1)) // power
    circle(512, 530, 104, gray(0.3))                                                    // d-pad ring
    circle(512, 530, 46, gray(0.46))                                                    // OK
    for (x, y) in [(512.0, 600.0), (512.0, 460.0), (442.0, 530.0), (582.0, 530.0)] { circle(x, y, 9, gray(0.7)) }
    gray(0.3).setFill()
    NSBezierPath(roundedRect: NSRect(x: 420, y: 250, width: 56, height: 130), xRadius: 28, yRadius: 28).fill()
    NSBezierPath(roundedRect: NSRect(x: 548, y: 250, width: 56, height: 130), xRadius: 28, yRadius: 28).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(px).write(to: out.appending(path: "icon_\(name).png"))
}
