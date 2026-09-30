// Renders OpusBar's app icon: the oneko Classic cat sitting (the menu bar's idle pose) on the green
// brand tile, so the icon is the same cat as everywhere else in the app. Classic is public-domain
// X11 oneko art (ADR 16). Writes a 1024 px master PNG and an .icns via iconutil.
//   swift scripts/make-icon.swift <output dir>
import AppKit

/// The sit frame, column 3 row 3 of the 8 x 4 sheet of 32 px frames.
let sheetURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appending(path: "../Sources/OpusBar/Resources/Coats/oneko-classic.png").standardized
let sheet = NSBitmapImageRep(data: try Data(contentsOf: sheetURL))!.cgImage!
let sit = sheet.cropping(to: CGRect(x: 3 * 32, y: 3 * 32, width: 32, height: 32))!

/// The cat's visible pixels within the frame (x, y from the top-left), so it is centered by what
/// the eye sees, not by the frame: the tail would otherwise push it right.
let visible: (minX: Int, maxX: Int, minY: Int, maxY: Int) = {
    var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
    let context = CGContext(data: &pixels, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 32 * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(sit, in: CGRect(x: 0, y: 0, width: 32, height: 32))
    var box = (minX: 32, maxX: -1, minY: 32, maxY: -1)
    // Memory rows run top-down, matching the frame's own rows.
    for y in 0..<32 { for x in 0..<32 where pixels[(y * 32 + x) * 4 + 3] > 127 {
        box = (min(box.minX, x), max(box.maxX, x), min(box.minY, y), max(box.maxY, y))
    } }
    return box
}()

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Below 64 px a sprite pixel is smaller than a screen pixel, so small sizes are the master scaled down smoothly.
func render(size: Int) -> NSBitmapImageRep {
    guard size < 64 else { return renderExact(size: size) }
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
    // One sprite pixel = 16 px at 1024, so every size from 64 up gets whole pixels (8, 4, 2, 1) and the
    // cat keeps the same proportion: its visible height is about half the tile, the margin Apple's
    // icon grid gives a glyph.
    let visibleWidth = CGFloat(visible.maxX - visible.minX + 1)
    let visibleHeight = CGFloat(visible.maxY - visible.minY + 1)
    let pixel = 16 * s
    let catX = (tile.midX - visibleWidth * pixel / 2 - CGFloat(visible.minX) * pixel).rounded()
    // Frame rows run top-down; the drawing origin is bottom-left.
    let catY = (tile.midY - visibleHeight * pixel / 2 - CGFloat(31 - visible.maxY) * pixel).rounded()
    let context = NSGraphicsContext.current!.cgContext
    context.interpolationQuality = .none
    context.draw(sit, in: CGRect(x: catX, y: catY, width: 32 * pixel, height: 32 * pixel))
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
