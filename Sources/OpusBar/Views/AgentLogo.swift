import AppKit
import OpusBarWire
import SwiftUI

/// An agent's mark in its series color: a template image, so it follows `Theme.agent` in light and dark.
struct AgentLogo: View {
    let agent: AgentKind
    var size: CGFloat = 12
    /// In place of the series color, e.g. charcoal on a yellow or red tile.
    var tint: Color?

    var body: some View {
        if let image = Self.image(for: agent) {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(tint ?? Theme.agent(agent)).frame(width: size, height: size)
        } else {
            Circle().fill(tint ?? Theme.agent(agent)).frame(width: size * 0.6, height: size * 0.6)
                .frame(width: size, height: size)
        }
    }

    private static func image(for agent: AgentKind) -> NSImage? {
        LogoImages.shared.image(named: agent.rawValue, in: "AgentLogos")
    }
}

/// How a session pays, as a small rounded tile like an app icon: the cloud's own logo for Bedrock, Vertex AI and
/// Foundry; a white symbol on a grey tile for a plan, API billing and a custom endpoint.
struct BillingLogo: View {
    let billing: SignInMethod
    var size: CGFloat = 10

    static func cornerRadius(_ size: CGFloat) -> CGFloat { size * 0.24 }

    var body: some View {
        if let image = LogoImages.shared.image(named: billing.rawValue, in: "BillingLogos") {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: Self.symbol(for: billing))
                .font(.system(size: size * 0.58, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: Self.cornerRadius(size), style: .continuous)
                    .fill(Color(white: 0.45)))
        }
    }

    static func symbol(for billing: SignInMethod) -> String {
        switch billing {
        case .subscription: "arrow.triangle.2.circlepath"
        case .apiKey: "key.fill"
        case .gateway: "point.3.connected.trianglepath.dotted"
        case .bedrock, .vertex, .foundry: "cloud.fill"
        }
    }
}

/// Who runs a session, in its brand color, with how it pays as a badge in its lower corner, like an app icon's badge.
/// The agent's logo is cut away around the badge tile so the two never touch, on any background.
struct AgentMark: View {
    let agent: AgentKind
    var billing: SignInMethod?
    /// One size everywhere (menu, Usage tab, Settings), so a profile reads the same in each.
    var size: CGFloat = 20

    private var badge: CGFloat { (size * 0.5).rounded() }
    /// How far the badge hangs past the logo's corner: half of it, like an app icon's badge.
    private var overhang: CGFloat { (size * 0.25).rounded() }
    private static let gap: CGFloat = 1.5

    var body: some View {
        AgentLogo(agent: agent, size: size)
            .mask {
                if billing != nil {
                    Rectangle()
                        .overlay(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: BillingLogo.cornerRadius(badge) + Self.gap, style: .continuous)
                                .frame(width: badge + Self.gap * 2, height: badge + Self.gap * 2)
                                .offset(x: overhang + Self.gap, y: overhang + Self.gap)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                } else {
                    Rectangle()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let billing { BillingLogo(billing: billing, size: badge).offset(x: overhang, y: overhang) }
            }
            // Room for the badge on every mark, so agent logos line up down the list, badged or not.
            .padding([.trailing, .bottom], overhang)
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help)
    }

    private var help: String {
        guard let billing else { return agent.displayName }
        return "\(agent.displayName) · \(billing.hasPlanLimits ? billing.label : "\(billing.label), billed per use")"
    }
}

/// Bundled logos, loaded once. Packaged app: Contents/Resources/<folder>. `swift run`: the SwiftPM resource
/// bundle next to the executable.
private final class LogoImages: @unchecked Sendable {
    static let shared = LogoImages()
    private let lock = NSLock()
    private var images: [String: NSImage?] = [:]

    func image(named name: String, in folder: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(folder)/\(name)"
        if let cached = images[key] { return cached }
        let image = Self.url(for: name, in: folder).flatMap(NSImage.init(contentsOf:))
        images[key] = image
        return image
    }

    private static func url(for name: String, in folder: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: folder) { return url }
        let dev = Bundle.main.bundleURL.appending(path: "OpusBar_OpusBar.bundle")
        return Bundle(url: dev)?.url(forResource: name, withExtension: "png", subdirectory: folder)
    }
}
