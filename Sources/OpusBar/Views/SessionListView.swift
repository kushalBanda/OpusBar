import OpusBarCore
import SwiftUI

/// The dropdown: a Sessions | Usage switch, then one card per session (loudest first) or the usage
/// summary, then Settings and Quit.
@MainActor
struct SessionListView: View {
    let store: SessionStore
    let preferences: Preferences
    let hooks: AgentHooksModel
    let usage: UsageModel
    let updater: Updater
    let layout: PopoverLayout
    var openSettings: (SettingsPane?) -> Void = { _ in }
    /// One card open at a time; the others stay compact.
    @State private var expandedId: String? = {
        #if DEBUG
        // `--expand <session id prefix>` opens that card on launch, for screenshots.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--expand"), i + 1 < args.count, !args.contains("--expand-later") { return args[i + 1] }
        #endif
        return nil
    }()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Kept while the app runs: the menu reopens on the tab it closed on.
    @State private var tab: DropdownTab = {
        #if DEBUG
        // `--tab usage` opens the Usage tab, for screenshots.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--tab"), i + 1 < args.count, let tab = DropdownTab(rawValue: args[i + 1]) { return tab }
        #endif
        return .sessions
    }()

    /// Idle sessions fold into one row once the list is long; the user can open it.
    @State private var showsIdle = false
    /// Height of the whole list, measured, so the scroll area is only as tall as it needs to be.
    @State private var contentHeight: CGFloat = 0

    private static let spring = Animation.spring(response: 0.32, dampingFraction: 1)

    var body: some View {
        let sections = SessionSections(store.sessions)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                SegmentedPicker(options: DropdownTab.allCases, selection: $tab, size: 13) { $0.title }
                    .padding(.bottom, 4)
                Text(tab == .sessions ? sections.summary : usageSummary).font(Theme.font(11, .regular)).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)
            // Both tabs stay laid out, one over the other, so the menu keeps the taller one's height and never
            // resizes or jumps on a switch; the hidden one takes no clicks and is hidden from VoiceOver.
            ZStack(alignment: .top) {
                page(.sessions) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let note = preferences.whatsNew, note.version == Updater.current?.description {
                            WhatsNewCard(note: note, fullNotes: { updater.openReleasePage(version: note.version) },
                                         dismiss: { preferences.whatsNew = nil })
                        }
                        if Preferences.offersConnect(anyConnected: hooks.anyConnected, anyConnectable: hooks.anyConnectable,
                                                     dismissed: preferences.connectCardDismissed) {
                            ConnectCard(connect: { openSettings(.agents) }, dismiss: { preferences.connectCardDismissed = true })
                        }
                        if sections.count == 0 {
                            EmptySessionsView()
                        } else {
                            list(sections)
                        }
                    }
                }
                page(.usage) {
                    UsageDropdownView(usage: usage, maxHeight: maxListHeight)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: tab)
            Divider()
            VStack(spacing: 0) {
                if let release = updater.offered {
                    MenuItemRow(title: "Update to OpusBar \(release.version)…", systemImage: "arrow.down.circle") { openSettings(.about) }
                }
                MenuItemRow(title: "Usage and Spend…", systemImage: "chart.bar") { openSettings(.usage) }
                MenuItemRow(title: "Settings…", systemImage: "gearshape", action: { openSettings(nil) })
                MenuItemRow(title: "Quit OpusBar", systemImage: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(10)
        .frame(width: 344, alignment: .leading)
        #if DEBUG
        // `--expand-later` opens the `--expand` card 2 s after the list appears, like a click would.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            guard args.contains("--expand-later"), let i = args.firstIndex(of: "--expand"), i + 1 < args.count else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(reduceMotion ? nil : Self.spring) { expandedId = args[i + 1] }
            }
            // `--collapse-later` closes it again 3 s later, to check the menu shrinks back.
            guard args.contains("--collapse-later") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation(reduceMotion ? nil : Self.spring) { expandedId = nil }
            }
        }
        #endif
        .font(Theme.font(13))
        .environment(\.catAnimates, preferences.animateCat)
        .environment(\.catCoat, preferences.coat)
        .environment(\.catPoses, preferences.poses)
    }

    /// One tab's content: shown when chosen, else invisible but still laid out.
    private func page(_ page: DropdownTab, @ViewBuilder content: () -> some View) -> some View {
        let shown = tab == page
        return content()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
    }

    /// Under the Usage tab's title: the free 24 hours at a glance.
    private var usageSummary: String {
        guard let totals = usage.last24h else { return "Reading your logs…" }
        guard totals.replies > 0 else { return "No usage in the last 24 h" }
        return "Last 24 h · \(UsageFormat.cost(totals.cost)) API value · \(UsageFormat.tokens(totals.tokens.total)) tokens"
    }

    /// Tallest the list may grow before it scrolls: most of the screen, leaving room for the menu bar,
    /// the header and the footer rows.
    private var maxListHeight: CGFloat {
        // The screen under the menu bar icon, not the focused one: they differ with several displays.
        // Leave room for the header, the footer rows and the popover's own margins.
        let screen = layout.screenHeight
        return max(200, min(screen * 0.6, screen - 280))
    }

    private func list(_ sections: SessionSections) -> some View {
        // Before the first measurement, start from an estimate so the frame isn't zero.
        let measured = contentHeight > 0 ? contentHeight : Self.estimatedHeight(sections, showsIdle: showsIdle)
        let visibleHeight = min(measured, maxListHeight)
        let scrolls = measured > visibleHeight + 0.5
        // A stable key of section membership and order: cards animate only when they change section.
        let orderKey = [sections.loud, sections.active, sections.idle].map { $0.map(\.id).joined(separator: ",") }
            .joined(separator: "|") + (showsIdle ? "+" : "-")
        return ScrollView(.vertical) {
            // Ticks once a second, and only while the popover is on screen.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                // A plain VStack on purpose: a lazy stack only builds the rows that fit its frame, so its
                // measured height shrinks with the frame and the rows below never appear.
                VStack(alignment: .leading, spacing: 6) {
                    group(sections.loud, title: "Attention", sections: sections, now: context.date)
                    group(sections.active, title: "Active", sections: sections, now: context.date)
                    idleGroup(sections, now: context.date)
                }
                // Measured directly: preferences don't reliably leave a ScrollView here.
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { updateHeight(proxy.size.height) }
                        .onChange(of: proxy.size.height) { _, height in updateHeight(height) }
                })
            }
        }
        // Visible while the list overflows, so there is always a cue that more sessions are below.
        .scrollIndicators(scrolls ? .visible : .never)
        .scrollDisabled(!scrolls)
        .frame(height: visibleHeight)
        .animation(reduceMotion ? nil : Self.spring, value: orderKey)
    }

    private func updateHeight(_ height: CGFloat) {
        if abs(height - contentHeight) > 0.5 { contentHeight = height }
    }

    /// Compact card about 58 pt, header about 26 pt, 6 pt spacing.
    static func estimatedHeight(_ sections: SessionSections, showsIdle: Bool) -> CGFloat {
        let rows = sections.loud.count + sections.active.count + (sections.isGrouped && !showsIdle ? 0 : sections.idle.count)
        let headers = sections.isGrouped ? [sections.loud, sections.active, sections.idle].filter { !$0.isEmpty }.count : 0
        let items = rows + headers
        return CGFloat(rows) * 58 + CGFloat(headers) * 26 + CGFloat(max(0, items - 1)) * 6
    }

    @ViewBuilder
    private func group(_ sessions: [Session], title: String, sections: SessionSections, now: Date) -> some View {
        if !sessions.isEmpty {
            if sections.isGrouped {
                Section { rows(sessions, now: now) } header: { SectionHeader(title: title, count: sessions.count) }
            } else {
                rows(sessions, now: now)
            }
        }
    }

    @ViewBuilder
    private func idleGroup(_ sections: SessionSections, now: Date) -> some View {
        if !sections.idle.isEmpty {
            if sections.isGrouped {
                Section {
                    if showsIdle { rows(sections.idle, now: now) }
                } header: {
                    SectionHeader(title: "Idle", count: sections.idle.count, isOpen: showsIdle) {
                        withAnimation(reduceMotion ? nil : Self.spring) { showsIdle.toggle() }
                    }
                }
            } else {
                rows(sections.idle, now: now)
            }
        }
    }

    private func rows(_ sessions: [Session], now: Date) -> some View {
        ForEach(sessions) { session in
            SessionRowView(session: session, now: now,
                           showsBranch: preferences.naming == .folderAndBranch,
                           isExpanded: expandedId.map { session.id.hasPrefix($0) } ?? false,
                           agentConnected: hooks.connectedAgents.contains(session.agent)) {
                withAnimation(reduceMotion ? nil : Self.spring) {
                    expandedId = expandedId.map { session.id.hasPrefix($0) } == true ? nil : session.id
                }
            }
            .transition(.opacity)
        }
    }
}

/// Facts about where the dropdown opens, set by the status item right before it shows.
@MainActor @Observable
final class PopoverLayout {
    /// Visible height of the screen holding the menu bar icon.
    var screenHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 800
}

/// Section title with its count. With `toggle`, the header folds its section (used for Idle).
private struct SectionHeader: View {
    let title: String
    let count: Int
    var isOpen = true
    var toggle: (() -> Void)?

    var body: some View {
        let label = HStack(spacing: 6) {
            Text(title).font(Theme.font(11, .semibold))
            Text("\(count)").font(Theme.font(11, .medium).monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            if toggle != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())

        if let toggle {
            Button(action: toggle) { label }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(count) sessions")
                .accessibilityHint(isOpen ? "Hides them" : "Shows them")
        } else {
            label.accessibilityElement(children: .combine)
        }
    }
}

private struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: 6) {
            CatView(state: nil)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(SessionState.idle.tileColor))
            Text("Nothing running").font(Theme.font(13, .semibold))
            Text("Start Claude Code or Codex in any terminal and it shows up here.")
                .font(Theme.font(11, .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
    }
}

/// First run: sessions already show up via discovery; connecting hooks adds live states.
/// Shown until an agent is connected or the user picks "Not now".
private struct ConnectCard: View {
    let connect: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CatView(state: .needsAttention)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.tileLight))
            VStack(alignment: .leading, spacing: 4) {
                Text("Get live states").font(Theme.font(13, .semibold))
                Text("Connect Claude Code or Codex so OpusBar sees when a session is thinking, working or needs you.")
                    .font(Theme.font(11, .regular)).opacity(0.72).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Connect…", action: connect).buttonStyle(.borderedProminent).tint(Theme.onColor)
                    Button("Not now", action: dismiss).buttonStyle(.borderless).foregroundStyle(Theme.onColor)
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .foregroundStyle(Theme.onColor)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.pink))
    }
}

/// A menu-style row: full-width hit area, highlight on hover.
private struct MenuItemRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Color.primary.opacity(0.07) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
