import OpusBarCore
import SwiftUI

/// The dropdown: header summary, one card per session (loudest first), then Settings and Quit.
@MainActor
struct SessionListView: View {
    let store: SessionStore
    var openSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sessions").font(.title2.weight(.semibold))
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            if store.sessions.isEmpty {
                EmptySessionsView()
            } else {
                // Ticks once a second, and only while the popover is on screen.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 6) {
                        ForEach(store.sessions) { session in
                            SessionRowView(session: session, now: context.date)
                        }
                    }
                }
            }
            Divider()
            VStack(spacing: 0) {
                MenuItemRow(title: "Settings…", systemImage: "gearshape", action: openSettings)
                MenuItemRow(title: "Quit OpusBar", systemImage: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(10)
        .frame(width: 344, alignment: .leading)
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
            Text("Nothing running").font(.body.weight(.semibold))
            Text("Start `claude` in any terminal and it shows up here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
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
