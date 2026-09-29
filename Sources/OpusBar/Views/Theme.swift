import AppKit
import CoreText
import SwiftUI

/// Mockup tokens (`mockups/_base.css`): beige canvas, charcoal ink, flat state tiles.
/// Green is the one interactive accent; blue/pink/yellow/red mean session state only.
enum Theme {
    static let canvas = dynamic(light: 0xF5F1E4, dark: 0x1F201D)
    static let canvas2 = dynamic(light: 0xE0DBCE, dark: 0x2C2E2A)
    static let surface = dynamic(light: 0xFFFDF7, dark: 0x2C2E2A)
    static let ink = dynamic(light: 0x2C2E2A, dark: 0xF5F1E4)
    static let green = Color(hex: 0x8ED462)
    static let pink = Color(hex: 0xEBC1FF)
    static let blue = Color(hex: 0x2BA0FF)
    static let yellow = Color(hex: 0xF5E211)
    static let red = Color(hex: 0xFF705D)
    static let idle = dynamic(light: 0xC2BCAD, dark: 0x4A4C46)
    /// Charcoal on every brand fill (AA).
    static let onColor = Color(hex: 0x2C2E2A)
    static let tileLight = Color(hex: 0xFFFDF7)

    /// Brand type: Inter (bundled, OFL), falling back to the system font if it failed to register.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        BrandFont.isAvailable ? .custom(BrandFont.family, size: size).weight(weight) : .system(size: size, weight: weight)
    }

    static let tileRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

/// Registers the bundled Inter for this process only (nothing is installed system-wide).
enum BrandFont {
    static let family = "Inter Variable"
    @MainActor private(set) static var isRegistered = false
    nonisolated(unsafe) private(set) static var isAvailable = false

    @MainActor
    static func register() {
        guard !isRegistered else { return }
        isRegistered = true
        let url = Bundle.main.url(forResource: "InterVariable", withExtension: "ttf")
            ?? Bundle(url: Bundle.main.bundleURL.appending(path: "OpusBar_OpusBar.bundle"))?.url(forResource: "InterVariable", withExtension: "ttf")
        guard let url else { return }
        var error: Unmanaged<CFError>?
        isAvailable = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            || NSFont(name: "InterVariable", size: 12) != nil // already registered
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// A bento tile: rounded, flat fill. Brand fills switch text to charcoal.
struct Tile<Content: View>: View {
    var fill: Color = Theme.surface
    var onColor = false
    /// Fill the height the parent offers (for side-by-side tiles that must line up).
    var stretches = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .frame(maxWidth: .infinity, maxHeight: stretches ? .infinity : nil, alignment: .topLeading)
            .padding(16)
            .foregroundStyle(onColor ? AnyShapeStyle(Theme.onColor) : AnyShapeStyle(Theme.ink))
            .background(RoundedRectangle(cornerRadius: Theme.tileRadius).fill(fill))
    }
}

/// Tile title + subline, per the mockup's `.t h3` / `.t p`.
struct TileHeading: View {
    let title: String
    var subtitle: String?
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: large ? 20 : 15, weight: .semibold))
                .kerning(large ? -0.6 : -0.3)
            if let subtitle {
                Text(subtitle).font(Theme.font(12, .regular)).opacity(0.72).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A single-select chip group (mockup `.chips`).
struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .font(Theme.font(13, .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(on ? Theme.surface : Theme.canvas))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .strokeBorder(on ? Theme.ink : .clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A read-only label pill (mockup `.pill`).
struct Pill: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.font(12, .regular))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Theme.canvas.opacity(0.8)))
    }
}

/// Whether the cat may animate. Settings "Motion" writes it; Reduce Motion still wins.
private struct CatAnimatesKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var catAnimates: Bool {
        get { self[CatAnimatesKey.self] }
        set { self[CatAnimatesKey.self] = newValue }
    }
}
