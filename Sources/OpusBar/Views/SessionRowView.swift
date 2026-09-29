import OpusBarCore
import OpusBarWire
import SwiftUI

/// One session card. Needs-you and error cards fill yellow or red so they read from across the room.
struct SessionRowView: View {
    let session: Session
    let now: Date
    var showsBranch = false

    /// Charcoal text on brand fills (AA on yellow and red).
    private static let onColor = Color(red: 0.173, green: 0.18, blue: 0.165)
    private static let tileLight = Color(red: 1.0, green: 0.992, blue: 0.969)

    private var isLoud: Bool { session.state == .needsAttention || session.state == .error }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CatView(state: session.state)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(isLoud ? Self.tileLight : session.state.tileColor))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName).font(Theme.font(13, .semibold)).lineLimit(1).layoutPriority(1)
                    AgentMark(agent: session.agent)
                    if showsBranch, let branch = session.branch {
                        Text(branch).font(Theme.font(11, .regular)).foregroundStyle(secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Text(detailLine).font(Theme.font(11, .regular)).foregroundStyle(secondary).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Text(Self.elapsed(from: session.stateSince, to: now))
                .font(Theme.font(11).monospacedDigit())
                .foregroundStyle(secondary)
                .fixedSize()
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(isLoud ? AnyShapeStyle(Self.onColor) : AnyShapeStyle(.primary))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(isLoud ? session.state.tileColor : Color.primary.opacity(0.05)))
        .help(session.isDiscovered
              ? "\(session.cwd)\nFound running (pid \(session.pid ?? 0)). Connect \(session.agent.displayName) in Settings for live states."
              : "\(session.cwd)\nSubagents: \(session.subagents)")
        .accessibilityElement(children: .combine)
    }

    private var secondary: AnyShapeStyle {
        isLoud ? AnyShapeStyle(Self.onColor.opacity(0.72)) : AnyShapeStyle(.secondary)
    }

    private var detailLine: String {
        let extras = [session.detail, session.subagents > 0 ? "\(session.subagents) subagent\(session.subagents == 1 ? "" : "s")" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
        // Discovered rows have no live state until the agent's hooks report in.
        let label = Self.label(for: session)
        return extras.isEmpty ? label : "\(label) · \(extras)"
    }

    /// Discovered rows: "Running" until a session file is matched, then "Active" or "Idle" from its activity.
    static func label(for session: Session) -> String {
        guard session.isDiscovered else { return session.state.label }
        if session.id.hasPrefix("pid:") { return "Running" }
        return session.state == .working ? "Active" : "Idle"
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds >= 3600 { return "\(seconds / 3600)h \(seconds % 3600 / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" }
        return "\(seconds)s"
    }
}

/// Which agent a card belongs to: a small outlined label, readable on every tile color.
struct AgentMark: View {
    let agent: AgentKind

    var body: some View {
        Text(agent.displayName)
            .font(Theme.font(10, .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(lineWidth: 1).opacity(0.35))
            .opacity(0.8)
            .accessibilityLabel("Agent: \(agent.displayName)")
    }
}

