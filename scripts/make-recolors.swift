// Makes OpusBar's own coats by recolouring the public-domain Classic oneko sheet (ADR 17).
// Classic has three colours: transparent, a white fill and a black outline. Each coat swaps the
// fill and outline; nothing else changes, so every pose lines up with Classic.
// Usage: swift scripts/make-recolors.swift <Coats folder>
import AppKit

struct Recolor { let name: String; let fill: UInt32; let fillAlpha: CGFloat; let outline: UInt32; let outlineAlpha: CGFloat }

let coats = [
    Recolor(name: "black", fill: 0x2B2B2E, fillAlpha: 1, outline: 0xD9D9DE, outlineAlpha: 1),
    Recolor(name: "gray", fill: 0x9A9CA3, fillAlpha: 1, outline: 0x2E3035, outlineAlpha: 1),
    Recolor(name: "silver", fill: 0xD8DCE3, fillAlpha: 1, outline: 0x6E7682, outlineAlpha: 1),
    Recolor(name: "ghost", fill: 0xCDB8F5, fillAlpha: 0.75, outline: 0x7B5CC4, outlineAlpha: 0.9),
]

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let classic = NSBitmapImageRep(data: try Data(contentsOf: folder.appending(path: "oneko-classic.png")))!

func rgba(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
    NSColor(deviceRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

for coat in coats {
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: classic.pixelsWide, pixelsHigh: classic.pixelsHigh,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for y in 0..<classic.pixelsHigh {
        for x in 0..<classic.pixelsWide {
            let c = classic.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            let color: NSColor
            if c.alphaComponent < 0.5 {
                color = .clear
            } else if c.redComponent > 0.5 {
                color = rgba(coat.fill, coat.fillAlpha)
            } else {
                color = rgba(coat.outline, coat.outlineAlpha)
            }
            out.setColor(color, atX: x, y: y)
        }
    }
    try out.representation(using: .png, properties: [:])!.write(to: folder.appending(path: "oneko-\(coat.name).png"))
    print("oneko-\(coat.name).png")
}
