import AppKit
import CoreText
import OpusBarCore
import OpusBarWire
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
    /// Each agent's series color in usage charts (validated as a pair for light and dark, CVD-safe).
    static func agent(_ agent: AgentKind) -> Color {
        switch agent {
        case .claude: dynamic(light: 0xD97757, dark: 0xCC6D4F)
        case .codex: dynamic(light: 0x5B7FFF, dark: 0x6F8CF5)
        }
    }

    /// The lifted segment of a segmented control: lighter than any surface it sits on, in both modes.
    static let pill = dynamic(light: 0xFFFDF7, dark: 0x55574F)

    /// Brand type: Inter (bundled, OFL), falling back to the system font if it failed to register.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        BrandFont.isAvailable ? .custom(BrandFont.family, size: size).weight(weight) : .system(size: size, weight: weight)
    }

    /// Pixel display type for playful titles ("Meow!"), falling back to the rounded system font.
    static func playful(_ size: CGFloat) -> Font {
        BrandFont.isPlayfulAvailable ? .custom(BrandFont.playfulFamily, size: size).weight(.bold)
            : .system(size: size, weight: .heavy, design: .rounded)
    }

    static let tileRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

/// Registers the bundled fonts for this process only (nothing is installed system-wide):
/// Inter for all text, Pixelify Sans for the playful display title.
enum BrandFont {
    static let family = "Inter Variable"
    static let playfulFamily = "Pixelify Sans"
    @MainActor private(set) static var isRegistered = false
    nonisolated(unsafe) private(set) static var isAvailable = false
    nonisolated(unsafe) private(set) static var isPlayfulAvailable = false

    @MainActor
    static func register() {
        guard !isRegistered else { return }
        isRegistered = true
        isAvailable = registerFont("InterVariable", postScriptName: "InterVariable")
        isPlayfulAvailable = registerFont("PixelifySans", postScriptName: "PixelifySans-Regular")
    }

    private static func registerFont(_ name: String, postScriptName: String) -> Bool {
        let url = Bundle.main.url(forResource: name, withExtension: "ttf")
            ?? Bundle(url: Bundle.main.bundleURL.appending(path: "OpusBar_OpusBar.bundle"))?.url(forResource: name, withExtension: "ttf")
        guard let url else { return false }
        var error: Unmanaged<CFError>?
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            || NSFont(name: postScriptName, size: 12) != nil // already registered
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

/// Which coat the cat wears. Settings writes it; a preview tile can override it for its own cat.
private struct CatCoatKey: EnvironmentKey {
    static let defaultValue = CatCoat.classic
}

extension EnvironmentValues {
    var catCoat: CatCoat {
        get { self[CatCoatKey.self] }
        set { self[CatCoatKey.self] = newValue }
    }
}

/// What the cat does per state. Settings writes it; a preview tile can override it for its own cat.
private struct CatPosesKey: EnvironmentKey {
    static let defaultValue = CatPoses.defaults
}

extension EnvironmentValues {
    var catPoses: CatPoses {
        get { self[CatPosesKey.self] }
        set { self[CatPosesKey.self] = newValue }
    }
}

/// A segmented control: a faint track with the chosen segment lifted on a pill. A pressed segment dims at
/// once; only the pill moves (critically damped spring, a cross-fade under Reduce Motion), so what the
/// selection drives elsewhere is not swept into the animation. Plain buttons, since gestures get no events
/// while a menu tracks the mouse.
struct SegmentedPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var size: CGFloat = 12
    let label: (Value) -> String
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var spring: Animation { .spring(response: 0.3, dampingFraction: 1) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    if !on { selection = option }
                } label: {
                    Text(label(option)).font(Theme.font(size, on ? .semibold : .medium)).lineLimit(1)
                    .padding(.horizontal, size * 0.8)
                    .padding(.vertical, size * 0.36)
                    .foregroundStyle(Theme.ink.opacity(on ? 1 : 0.6))
                    .background {
                        if on {
                            Capsule().fill(Theme.pill)
                                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(SegmentButtonStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.ink.opacity(0.08)))
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Self.spring, value: selection)
    }
}

/// Feedback on press, not on release: the segment dims while held.
private struct SegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
