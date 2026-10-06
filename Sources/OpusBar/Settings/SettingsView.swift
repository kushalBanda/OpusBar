import OpusBarCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, cat, agents, usage, notifications, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .cat: "Cat"
        case .agents: "Agents"
        case .usage: "Usage"
        case .notifications: "Notifications"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .cat: "cat"
        case .agents: "powerplug"
        case .usage: "chart.bar.fill"
        case .notifications: "bell"
        case .about: "info.circle"
        }
    }

    var iconFill: Color {
        switch self {
        case .general: Color(hex: 0xC2BCAD) // fixed warm grey: the dark glyph needs a light tile in both modes
        case .cat: Theme.green // same tile as the identity card and app icon
        case .agents: Theme.pink
        case .usage: Theme.blue
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
    let usage: UsageModel
    let updater: Updater

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
        .environment(\.catCoat, preferences.coat)
        .environment(\.catPoses, preferences.poses)
        .font(Theme.font(13)) // default for buttons and labels without their own font
        .frame(width: 820, height: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                CatView(state: .idle, points: 32)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.green))
                VStack(alignment: .leading, spacing: 3) {
                    Text("OpusBar").font(Theme.font(14, .semibold)).kerning(-0.3)
                    Text(AboutPane.version).font(Theme.font(11, .regular)).opacity(0.6)
                }
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
        case .cat: CatPane(preferences: preferences)
        case .agents: AgentsSettingsView(model: hooks, store: store)
        case .usage: UsagePane(usage: usage)
        case .notifications: NotificationsPane(preferences: preferences, notifier: notifier, usage: usage)
        case .about: AboutPane(updater: updater, preferences: preferences)
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
                icon
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

    /// The Cat pane shows the chosen coat in its idle pose, held still; 16 pt keeps the 32 px frame 1:1 on Retina.
    @ViewBuilder
    private var icon: some View {
        if pane == .cat {
            CatView(state: nil, points: 16).environment(\.catAnimates, false)
        } else {
            Image(systemName: pane.systemImage)
                .font(Theme.font(12, .medium))
                .foregroundStyle(Theme.onColor)
        }
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
    let usage: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Notifications",
                      lead: "Get a macOS notification when a session changes or a plan limit runs low or resets. macOS asks for permission the first time.")
            Tile {
                row(.needsAttention, "A session needs you", "Permission prompts and questions.", $preferences.notifyNeedsYou)
                Divider().opacity(0.5)
                row(.error, "A session hits an error", nil, $preferences.notifyError)
                Divider().opacity(0.5)
                row(.done, "A session finishes", "Off by default. Can get chatty with many sessions.", $preferences.notifyDone)
            }
            limitResets.padding(.top, 8)
            accessNote.padding(.top, 12)
        }
        .onAppear { notifier.refreshAccess() }
        .onChange(of: preferences.anyNotificationOn) { _, on in if on { notifier.requestAccess() } }
    }

    /// Plan limits: a switch for resets and one for warnings, then one per account for both, each on until turned off.
    private var limitResets: some View {
        Tile {
            limitRow("arrow.clockwise.circle.fill", "A plan limit resets",
                     "When a Claude or Codex window you've used renews, like the 5-hour or weekly limit.",
                     $preferences.notifyLimitReset)
            Divider().opacity(0.5)
            limitRow("gauge.with.dots.needle.67percent", "A plan limit is nearly used",
                     "At 80% and again at 95%, once per window.", $preferences.notifyLimitWarning)
            if usage.limits.isEmpty {
                Text("Accounts show here once their limits are known. Claude Code saves them when it checks an account.")
                    .font(Theme.font(12, .regular)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }
            ForEach(usage.limits) { limits in
                Divider().opacity(0.5)
                HStack(spacing: 10) {
                    AgentLogo(agent: limits.agent, size: 14).padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(limits.agent.displayName).font(Theme.font(13, .medium))
                        if let label = limits.label {
                            Text(label).font(Theme.font(11, .regular)).opacity(0.6).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer()
                    Toggle(limits.label ?? limits.agent.displayName, isOn: Binding(
                        get: { !preferences.limitResetMuted.contains(limits.id) },
                        set: { on in
                            if on { preferences.limitResetMuted.remove(limits.id) } else { preferences.limitResetMuted.insert(limits.id) }
                        }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Theme.green)
                }
                .padding(.vertical, 6)
                .disabled(!anyLimitNotice)
                .opacity(anyLimitNotice ? 1 : 0.5)
            }
        }
    }

    private var anyLimitNotice: Bool { preferences.notifyLimitReset || preferences.notifyLimitWarning }

    private func limitRow(_ symbol: String, _ title: String, _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Theme.onColor)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.green))
            TileHeading(title: title, subtitle: subtitle)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).tint(Theme.green)
        }
        .padding(.vertical, 8)
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
    let updater: Updater
    @Bindable var preferences: Preferences

    static var version: String {
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
                        Text(Self.version).font(Theme.font(14, .regular))
                    }
                }
                .padding(8)
            }
            UpdatesTile(updater: updater, preferences: preferences)
            Tile {
                TileHeading(title: "Privacy",
                            subtitle: "Runs entirely on your Mac. No account, no telemetry. OpusBar reads your agents' session files, logs and hook events, and the plan limits Claude Code caches or hands its status line, locally. The only thing it sends is the update check: a request to GitHub for the latest version, carrying OpusBar's version and nothing about you. Usage and Spend keeps only token counts, never your prompts or replies.")
            }
        }
    }
}

/// Updates: what the last check found, Check Now, and the automatic check switch. An offered release
/// installs on quit when automatic installs are on, or on a click.
@MainActor
private struct UpdatesTile: View {
    let updater: Updater
    @Bindable var preferences: Preferences

    var body: some View {
        Tile {
            HStack(alignment: .center, spacing: 14) {
                TileHeading(title: title, subtitle: subtitle)
                Spacer()
                actions
            }
            .padding(.vertical, 4)
            Divider().opacity(0.5)
            HStack {
                TileHeading(title: "Check for updates automatically",
                            subtitle: "Once a day, a request to GitHub for the latest version. Off: no request at all.")
                Spacer()
                Toggle("Check for updates automatically", isOn: $preferences.checkForUpdates)
                    .labelsHidden().toggleStyle(.switch).tint(Theme.green)
            }
            .padding(.vertical, 4)
            Divider().opacity(0.5)
            HStack {
                TileHeading(title: "Install updates automatically",
                            subtitle: "A new version is downloaded and checked in the background, then swapped in when you quit OpusBar.")
                Spacer()
                Toggle("Install updates automatically", isOn: $preferences.installUpdatesAutomatically)
                    .labelsHidden().toggleStyle(.switch).tint(Theme.green)
            }
            .padding(.vertical, 4)
            .disabled(!preferences.checkForUpdates)
            .opacity(preferences.checkForUpdates ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch updater.state {
        case .available:
            Button("Release Notes") { updater.openReleasePage() }
            Button("Update and Relaunch") { updater.install() }
                .buttonStyle(.borderedProminent).tint(Theme.green).foregroundStyle(Theme.onColor)
        case .ready:
            Button("Release Notes") { updater.openReleasePage() }
            Button("Relaunch Now") { updater.install() }
                .buttonStyle(.borderedProminent).tint(Theme.green).foregroundStyle(Theme.onColor)
        case .checking, .installing:
            ProgressView().controlSize(.small)
        case .failed where updater.offered != nil:
            Button("Download from GitHub") { updater.openReleasePage() }
            Button("Try Again") { updater.install() }
        default:
            Button("Check Now") { updater.check() }
        }
    }

    private var title: String {
        switch updater.state {
        case .available(let release): "OpusBar \(release.version) is available"
        case .ready(let release): "OpusBar \(release.version) is ready"
        case .installing(let release): "Installing OpusBar \(release.version)…"
        case .checking: "Checking for updates…"
        case .upToDate: "OpusBar is up to date"
        case .failed: "Update problem"
        case .idle: "Updates"
        }
    }

    private var subtitle: String? {
        switch updater.state {
        case .available: "Downloaded from GitHub and checked against OpusBar's signature before anything changes."
        case .ready: "Installs the next time you quit OpusBar, or now if you relaunch."
        case .installing: "OpusBar quits and opens again when it's done."
        case .upToDate(let date): "Checked \(date.formatted(date: .omitted, time: .shortened))."
        case .failed(let reason): reason
        case .checking: nil
        case .idle: Updater.current == nil ? "This is a development build; it doesn't update itself." : nil
        }
    }
}
