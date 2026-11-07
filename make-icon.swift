// Draws Sweep's app icon and writes an .iconset folder for iconutil. Usage: swift make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// A white copy of an SF Symbol, drawn as vector shapes at the target size so it stays sharp.
func symbol(_ name: String, size: CGFloat) -> NSImage {
    let shape = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: size, weight: .semibold))!
    return NSImage(size: shape.size, flipped: false) { rect in
        shape.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

/// Draws the icon on a 1024-point canvas, scaled to `px` pixels.
func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // macOS icon grid: an 824-point rounded square centred on the canvas, with a soft shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(red: 0.20, green: 0.84, blue: 0.75, alpha: 1),
               ending: NSColor(red: 0.12, green: 0.38, blue: 0.86, alpha: 1))!.draw(in: shape, angle: -90)

    // A drive with sparkles: disk space, cleaned.
    let drive = symbol("internaldrive.fill", size: 330)
    let ds = drive.size
    drive.draw(in: NSRect(x: 512 - ds.width / 2, y: 430 - ds.height / 2, width: ds.width, height: ds.height))
    let sparkles = symbol("sparkles", size: 210)
    let ss = sparkles.size
    sparkles.draw(in: NSRect(x: 640 - ss.width / 2, y: 650 - ss.height / 2, width: ss.width, height: ss.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(px: size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(px: size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
