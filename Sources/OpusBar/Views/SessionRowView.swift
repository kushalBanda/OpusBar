import AppKit
import OpusBarCore
import OpusBarWire
import SwiftUI

/// One session card. Needs-you and error cards fill yellow or red so they read from across the room.
struct SessionRowView: View {
    let session: Session
    let now: Date
    var showsBranch = false
    /// Click toggles an inline details panel: where the session is, how OpusBar sees it, and quick actions.
    var isExpanded = false
    /// Whether this session's agent already has OpusBar hooks, which changes the hint for found-running rows.
    var agentConnected = false
    var onTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Keeps the details in the layout while they fade out on collapse. The list measures its final
    /// height at once, so removing them right away shrinks the card and cuts the fade off.
    @State private var detailsLeaving = false

    /// Charcoal text on brand fills (AA on yellow and red).
    private static let onColor = Color(red: 0.173, green: 0.18, blue: 0.165)
    private static let tileLight = Color(red: 1.0, green: 0.992, blue: 0.969)

    private var isLoud: Bool { session.state == .needsAttention || session.state == .error }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summary
            if isExpanded || detailsLeaving {
                SessionDetails(session: session, now: now, secondary: secondary, agentConnected: agentConnected)
                    .opacity(isExpanded ? 1 : 0)
                    .transition(.opacity)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            guard !expanded, !reduceMotion else { return }
            detailsLeaving = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { detailsLeaving = false }
        }
        .foregroundStyle(isLoud ? AnyShapeStyle(Self.onColor) : AnyShapeStyle(.primary))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(isLoud ? session.state.tileColor : Color.primary.opacity(isExpanded ? 0.08 : 0.05)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Hides details" : "Shows details")
    }

    private var summary: some View {
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
            Text(Self.elapsed(from: Self.timerStart(for: session), to: now))
                .font(Theme.font(11).monospacedDigit())
                .foregroundStyle(secondary)
                .fixedSize()
                .frame(maxHeight: .infinity, alignment: .top)
                .help(timerHelp)
        }
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
        let label = [Self.label(for: session), session.distinctTitle, session.host?.appName]
            .compactMap { $0 }.joined(separator: " · ")
        return extras.isEmpty ? label : "\(label) · \(extras)"
    }

    /// Discovered rows: "Running" until a session file is matched, then "Active" or "Idle" from its activity.
    static func label(for session: Session) -> String {
        guard session.isDiscovered else { return session.state.label }
        if session.id.hasPrefix("pid:") { return "Running" }
        return session.state == .working ? "Active" : "Idle"
    }

    /// The corner timer means different things per state; say which on hover.
    private var timerHelp: String {
        let span = Self.elapsed(from: Self.timerStart(for: session), to: now)
        let what = switch session.state {
        case .thinking, .working: session.turnStartedAt == nil ? "\(Self.label(for: session)) for \(span)" : "This turn has run \(span)"
        default: "\(Self.label(for: session)) for \(span)"
        }
        return "\(what). Session started \(Self.elapsed(from: session.startedAt, to: now)) ago."
    }

    /// During a turn the timer counts the whole turn, not just the current tool or pause, so it
    /// doesn't reset on every tool call.
    static func timerStart(for session: Session) -> Date {
        switch session.state {
        case .thinking, .working: session.turnStartedAt ?? session.stateSince
        default: session.stateSince
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        ElapsedFormat.short(from: start, to: now)
    }
}

/// The expanded part of a card: the facts about the session.
private struct SessionDetails: View {
    let session: Session
    let now: Date
    let secondary: AnyShapeStyle
    let agentConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                row("Folder", Self.tildePath(session.cwd))
                if let branch = session.branch { row("Branch", branch) }
                if let title = session.title { row("Session", title) }
                if let place = session.host?.label ?? session.term?.termProgram.map(Self.terminalName) { row("Where", place) }
                row("Started", "\(ElapsedFormat.short(from: session.startedAt, to: now)) ago")
                row("Last activity", "\(ElapsedFormat.short(from: session.lastEventAt, to: now)) ago")
                row("States", session.isDiscovered ? "Found running, no live states" : "Live from hooks")
            }
            if session.isDiscovered {
                // Hooks load when a session starts, so sessions that predate connecting stay without live states.
                Text(liveStatesHint)
                    .font(Theme.font(11, .regular)).foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 52) // lines up with the text column, past the cat tile
    }

    private var liveStatesHint: String {
        agentConnected
            ? "This session started before OpusBar was connected. To see its live state here, restart it."
            : "Connect \(session.agent.displayName) in Settings, then restart it, to see its live state here."
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(Theme.font(11, .regular)).foregroundStyle(secondary)
            Text(value).font(Theme.font(11, .medium)).lineLimit(2).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    static func tildePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func terminalName(_ program: String) -> String {
        switch program {
        case "Apple_Terminal": "Terminal"
        case "iTerm.app": "iTerm"
        case "vscode": "VS Code"
        case "WarpTerminal": "Warp"
        case "ghostty": "Ghostty"
        default: program
        }
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

