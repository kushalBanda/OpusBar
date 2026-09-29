import OpusBarCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, agents, notifications, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .agents: "Agents"
        case .notifications: "Notifications"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .agents: "powerplug"
        case .notifications: "bell"
        case .about: "info.circle"
        }
    }

    var iconFill: Color {
        switch self {
        case .general: Theme.idle
        case .agents: Theme.pink
        case .notifications: Theme.yellow
        case .about: Theme.red
        }
    }
}

/// Which pane is showing. Shared with the window controller so the dropdown can open a given pane.
@MainActor @Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
}

/// The Settings window: sidebar with the cat identity card, one pane at a time.
@MainActor
struct SettingsView: View {
    @Bindable var navigation: SettingsNavigation
    let preferences: Preferences
    let hooks: AgentHooksModel
    let launchAtLogin: LaunchAtLogin
    let notifier: SessionNotifier
    let store: SessionStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollViewReader { proxy in
                ScrollView {
                    pane
                        .id(navigation.pane)
                        .transition(.opacity)
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                #if DEBUG
                // `--scroll <anchor id>` scrolls to that view on open, for screenshots.
                .onAppear {
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "--scroll"), i + 1 < args.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(args[i + 1], anchor: .bottom) }
                    }
                }
                #endif
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: navigation.pane)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .environment(\.catAnimates, preferences.animateCat)
        .font(Theme.font(13)) // default for buttons and labels without their own font
        .frame(width: 820, height: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                CatView(state: .idle, points: 32)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.green))
                Text("OpusBar").font(Theme.font(14, .semibold)).kerning(-0.3)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.tileRadius).fill(Theme.surface))
            .padding(.bottom, 12)
            ForEach(SettingsPane.allCases) { pane in
                SidebarRow(pane: pane, selected: navigation.pane == pane) { navigation.pane = pane }
            }
            Spacer()
            Button("Quit OpusBar") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(Theme.font(13, .medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.surface))
        }
        .padding(.horizontal, 14)
        .padding(.top, 40) // clears the traffic lights over the full-size content view
        .padding(.bottom, 16)
        .frame(width: 220)
        .background(Theme.canvas2.opacity(0.6))
    }

    @ViewBuilder
    private var pane: some View {
        switch navigation.pane {
        case .general: GeneralPane(preferences: preferences, launchAtLogin: launchAtLogin)
        case .agents: AgentsSettingsView(model: hooks, store: store)
        case .notifications: NotificationsPane(preferences: preferences, notifier: notifier)
        case .about: AboutPane()
        }
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.systemImage)
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.onColor)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(pane.iconFill))
                Text(pane.title).font(Theme.font(13, .medium))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .foregroundStyle(selected ? Theme.canvas : Theme.ink)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(selected ? Theme.ink : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Big pane title per the mockup (34 pt, tight tracking).
struct PaneTitle: View {
    let title: String
    var lead: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(34, .medium)).kerning(-1.7)
            if let lead {
                Text(lead).font(Theme.font(14, .regular)).opacity(0.66).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 20)
    }
}

// MARK: - General

@MainActor
struct GeneralPane: View {
    @Bindable var preferences: Preferences
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneTitle(title: "General")
            // Both columns share one height: the cat tile grows to match the two setting tiles.
            HStack(alignment: .top, spacing: 8) {
                Tile(fill: Theme.green, onColor: true, stretches: true) {
                    HStack(spacing: 16) {
                        CatView(state: .idle, points: 64)
                            .frame(width: 88, height: 88)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.tileLight.opacity(0.5)))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Meow!").font(Theme.playful(34))
                            Text("It lives in the menu bar and in every session card.")
                                .font(Theme.font(12, .regular)).opacity(0.72).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 12)
                    CatLegend()
                }
                VStack(spacing: 8) {
                    // Content centered vertically: the tiles are taller than a toggle row.
                    Tile(stretches: true) {
                        Spacer(minLength: 0)
                        SettingToggle(title: "Start at login", subtitle: "Open with your Mac.",
                                      isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                        if let note = launchAtLogin.note {
                            Text(note).font(Theme.font(11, .regular)).opacity(0.72).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    Tile(stretches: true) {
                        Spacer(minLength: 0)
                        SettingToggle(title: "Motion", subtitle: "Animate the cat.", isOn: $preferences.animateCat)
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: 220)
            }
            .fixedSize(horizontal: false, vertical: true)
            Tile {
                TileHeading(title: "Sessions")
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Remove finished sessions after").font(Theme.font(12, .regular)).opacity(0.72)
                        ChipPicker(options: FinishedRetention.allCases, selection: $preferences.retention) { $0.label }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Name sessions by").font(Theme.font(12, .regular)).opacity(0.72)
                        ChipPicker(options: SessionNaming.allCases, selection: $preferences.naming) { $0.label }
                    }
                }
                .padding(.top, 4)
            }
            Text("With Reduce Motion on, the cat always holds still.")
                .font(Theme.font(12, .regular)).opacity(0.5).padding(.top, 8)
        }
        .onAppear { launchAtLogin.refresh() }
    }
}

/// Title and subtitle on the left, the switch pinned to the trailing edge, so switches line up across tiles.
struct SettingToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TileHeading(title: title, subtitle: subtitle)
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Theme.green)
        }
    }
}

/// What each pose means: the five states a card can show, with the live cat for each.
/// Teaches the menu bar glyph at a glance, and fills the cat tile with something useful.
private struct CatLegend: View {
    private let states: [SessionState] = [.working, .thinking, .needsAttention, .done, .error]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(states, id: \.self) { state in
                VStack(spacing: 4) {
                    CatView(state: state, points: 32)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(state.tileColor))
                    Text(state.label).font(Theme.font(10, .medium)).lineLimit(1).fixedSize()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.tileLight.opacity(0.55)))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Notifications

@MainActor
struct NotificationsPane: View {
    @Bindable var preferences: Preferences
    let notifier: SessionNotifier

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Notifications",
                      lead: "Get a macOS notification when a session changes. macOS asks for permission the first time.")
            Tile {
                row(.needsAttention, "A session needs you", "Permission prompts and questions.", $preferences.notifyNeedsYou)
                Divider().opacity(0.5)
                row(.error, "A session hits an error", nil, $preferences.notifyError)
                Divider().opacity(0.5)
                row(.done, "A session finishes", "Off by default. Can get chatty with many sessions.", $preferences.notifyDone)
            }
            accessNote.padding(.top, 12)
        }
        .onAppear { notifier.refreshAccess() }
    }

    @ViewBuilder
    private var accessNote: some View {
        switch notifier.access {
        case .denied:
            HStack {
                Text("Notifications are off for OpusBar in System Settings.").font(Theme.font(12, .regular)).opacity(0.72)
                Button("Open Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .unavailable:
            Text("Notifications only work from OpusBar.app, not `swift run`.").font(Theme.font(12, .regular)).opacity(0.5)
        case .notAsked, .allowed:
            Text("Clicking a notification opens the OpusBar menu.").font(Theme.font(12, .regular)).opacity(0.5)
        }
    }

    private func row(_ state: SessionState, _ title: String, _ subtitle: String?, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            CatView(state: state, points: 32)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(state.tileColor))
            TileHeading(title: title, subtitle: subtitle)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).tint(Theme.green)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - About

struct AboutPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        return "Version \(short)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Tile(fill: Theme.green, onColor: true) {
                HStack(spacing: 22) {
                    CatView(state: .done, points: 96)
                        .frame(width: 128, height: 128)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.tileLight.opacity(0.5)))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpusBar").font(Theme.font(34, .medium)).kerning(-1.7)
                        Text(version).font(Theme.font(14, .regular))
                    }
                }
                .padding(8)
            }
            Tile {
                TileHeading(title: "Privacy",
                            subtitle: "Runs entirely on your Mac. No account, no telemetry. OpusBar reads your agents' session files and hook events locally and sends nothing anywhere.")
            }
        }
    }
}
