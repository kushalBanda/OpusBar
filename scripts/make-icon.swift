// Renders OpusBar's app icon: an original pixel cat (drawn for OpusBar, not derived from oneko)
// on the green brand tile. Writes a 1024 px master PNG and an .icns via iconutil.
//   swift scripts/make-icon.swift <output dir>
import AppKit

/// 22 x 22 pixel cat. K outline, W fur, P inner ear and nose, E eye, . empty.
let cat = [
    "......................",
    "...KK............KK...",
    "...KPK..........KPK...",
    "...KPPK........KPPK...",
    "...KPPWKKKKKKKKWPPK...",
    "..KWWWWWWWWWWWWWWWWK..",
    "..KWWWWWWWWWWWWWWWWK..",
    ".KWWWWWWWWWWWWWWWWWWK.",
    ".KWWWWEEWWWWWWEEWWWWK.",
    ".KWWWWEEWWWWWWEEWWWWK.",
    ".KWWWWEEWWWWWWEEWWWWK.",
    ".KWWWWWWWWPPWWWWWWWWK.",
    "..KWWWWWWWKKWWWWWWWK..",
    "...KKWWWWWWWWWWWWKK...",
    "....KWWWWWWWWWWWWK.KK.",
    "...KWWWWWWWWWWWWWWKKWK",
    "..KWWWWWWWWWWWWWWWWKWK",
    "..KWWWWWWWWWWWWWWWWKWK",
    "..KWWWWKWWWWWWKWWWWKWK",
    "..KWWWWKWWWWWWKWWWWWK.",
    "...KKKKKKKKKKKKKKKKK..",
    "......................",
]

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let palette: [Character: NSColor] = [
    "K": color(0x2C2E2A), "W": color(0xFFFDF7), "P": color(0xEBC1FF), "E": color(0x2C2E2A),
]

/// Below 128 px a whole-pixel grid no longer fits, so small sizes are the master scaled down smoothly.
func render(size: Int) -> NSBitmapImageRep {
    guard size < 128 else { return renderExact(size: size) }
    let master = renderExact(size: 1024)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy,
                fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func renderExact(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    // macOS icon grid: 824 pt tile centered in 1024, continuous-corner radius ~185.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(0x8ED462).setFill()
    NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s).fill()
    NSGraphicsContext.restoreGraphicsState()
    // Whole pixels only, so edges stay crisp at every size.
    let pixel = max(1, (CGFloat(size) * 0.56 / CGFloat(cat.count)).rounded(.down))
    let grid = pixel * CGFloat(cat.count)
    let originX = ((CGFloat(size) - grid) / 2).rounded()
    let originY = ((CGFloat(size) - grid) / 2 - pixel * 0.5).rounded()
    for (row, line) in cat.enumerated() {
        for (col, char) in line.enumerated() {
            guard let fill = palette[char] else { continue }
            fill.setFill()
            NSRect(x: originX + CGFloat(col) * pixel, y: originY + CGFloat(cat.count - 1 - row) * pixel,
                   width: pixel, height: pixel).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon")
let iconset = out.appending(path: "OpusBar.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(size: base * scale).representation(using: .png, properties: [:])!.write(to: iconset.appending(path: name))
    }
}
try render(size: 1024).representation(using: .png, properties: [:])!.write(to: out.appending(path: "OpusBar-1024.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.appending(path: "OpusBar.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote \(out.appending(path: "OpusBar.icns").path)")
