import OpusBarCore
import SwiftUI

/// The dropdown: header summary, one card per session (loudest first), then Settings and Quit.
@MainActor
struct SessionListView: View {
    let store: SessionStore
    let preferences: Preferences
    let hooks: AgentHooksModel
    var openSettings: (SettingsPane?) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sessions").font(Theme.font(17, .semibold))
                Text(summary).font(Theme.font(11, .regular)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            if Preferences.offersConnect(anyConnected: hooks.anyConnected, anyConnectable: hooks.anyConnectable,
                                         dismissed: preferences.connectCardDismissed) {
                ConnectCard(connect: { openSettings(.agents) }, dismiss: { preferences.connectCardDismissed = true })
            }
            if store.sessions.isEmpty {
                EmptySessionsView()
            } else {
                // Ticks once a second, and only while the popover is on screen.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 6) {
                        ForEach(store.sessions) { session in
                            SessionRowView(session: session, now: context.date, showsBranch: preferences.naming == .folderAndBranch)
                        }
                    }
                }
            }
            Divider()
            VStack(spacing: 0) {
                MenuItemRow(title: "Settings…", systemImage: "gearshape", action: { openSettings(nil) })
                MenuItemRow(title: "Quit OpusBar", systemImage: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(10)
        .frame(width: 344, alignment: .leading)
        .font(Theme.font(13))
        .environment(\.catAnimates, preferences.animateCat)
    }

    private var summary: String {
        let aggregate = store.aggregate
        guard !store.sessions.isEmpty else { return "No sessions" }
        let needs = aggregate.needsYouCount > 0 ? ", \(aggregate.needsYouCount) need\(aggregate.needsYouCount == 1 ? "s" : "") you" : ""
        return "\(aggregate.activeCount) active\(needs)"
    }
}

private struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: 6) {
            CatView(state: nil)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(SessionState.idle.tileColor))
            Text("Nothing running").font(Theme.font(13, .semibold))
            Text("Start Claude Code, Codex, pi or OMP in any terminal and it shows up here.")
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
