import AppKit

// Finder uses both TIFF representations at the same logical size.
let size = NSSize(width: 640, height: 400)
let image = NSImage(size: size)

func centered(_ text: String, top: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let string = text as NSString
    let measured = string.size(withAttributes: attributes)
    string.draw(at: NSPoint(x: (size.width - measured.width) / 2,
                           y: size.height - top - measured.height), withAttributes: attributes)
}

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGradient(starting: NSColor(srgbRed: 0.99, green: 0.99, blue: 0.99, alpha: 1),
               ending: NSColor(srgbRed: 0.94, green: 0.95, blue: 0.96, alpha: 1))!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)
    centered("Peek for Codex", top: 46, font: .systemFont(ofSize: 26, weight: .semibold),
             color: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1))
    centered("Drag to Applications", top: 87, font: .systemFont(ofSize: 14),
             color: NSColor(srgbRed: 0.42, green: 0.44, blue: 0.47, alpha: 1))
    let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 30, weight: .regular))!
        .withSymbolConfiguration(.init(paletteColors: [NSColor(srgbRed: 0.57, green: 0.59, blue: 0.62, alpha: 1)]))!
    arrow.draw(in: NSRect(x: 300, y: 174, width: 40, height: 32))
    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(bitmap)
}

guard CommandLine.arguments.count == 2, let data = image.tiffRepresentation else {
    fatalError("Usage: swift Support/DiskImageBackground.swift OUTPUT.tiff")
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
