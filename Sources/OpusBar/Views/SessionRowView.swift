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
    /// Tokens and cost logged under this session so far, subagents included; nil until the logs are read.
    var usage: SessionUsage?
    var onTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Charcoal text on brand fills (AA on yellow and red).
    private static let onColor = Color(red: 0.173, green: 0.18, blue: 0.165)
    private static let tileLight = Color(red: 1.0, green: 0.992, blue: 0.969)

    private var isLoud: Bool { session.state == .needsAttention || session.state == .error }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summary
            if !session.subagents.isEmpty {
                SubagentList(subagents: session.subagents, now: now, secondary: secondary, showsAll: isExpanded,
                             usage: usage?.bySubagent ?? [:])
                    .transition(.opacity)
            }
            // Opens and closes in the tap's spring; the menu holds its height until a collapse settles.
            if isExpanded {
                SessionDetails(session: session, now: now, secondary: secondary, agentConnected: agentConnected)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1), value: session.subagents.map(\.id))
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
                    if let mode = session.permissionMode, !mode.isDefault {
                        ModeMark(mode: mode, onLoudTile: isLoud)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
                    }
                    if showsBranch, let branch = session.branch {
                        Text(branch).font(Theme.font(11, .regular)).foregroundStyle(secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Text(detailLine).font(Theme.font(11, .regular)).foregroundStyle(secondary).lineLimit(1)
                if let total = usage?.total, total.replies > 0 {
                    UsageMetrics(total: total, secondary: secondary).padding(.top, 2)
                }
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
        // Shift+Tab in the agent swaps the badge in place: critically damped, no bounce.
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1), value: session.permissionMode)
        .accessibilityElement(children: .combine)
    }

    private var secondary: AnyShapeStyle {
        isLoud ? AnyShapeStyle(Self.onColor.opacity(0.72)) : AnyShapeStyle(.secondary)
    }

    private var detailLine: String {
        // Subagents have their own rows below.
        let extras = session.detail ?? ""
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
                if let mode = session.permissionMode { row("Mode", mode.label) }
                if let signIn = session.signIn, !signIn.hasPlanLimits { row("Billing", signIn.label) }
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

/// The session's spend on the card face, glyph then figure: ↑ new input, ↓ output, ⛁r cache read, then dollars.
/// Claude Code caches every prompt up to its last token, so the API's `input_tokens` stays at a few per reply
/// while prompts and tool results arrive as cache writes: ↑ adds the two, the input the model saw for the
/// first time. Cache reads are the conversation re-read each reply. Counts include subagents.
private struct UsageMetrics: View {
    let total: UsageTotals
    let secondary: AnyShapeStyle

    var body: some View {
        // Never wider than the text column: a fixed-width row pushed every card past the menu's edge.
        // Roomy gaps when they fit, tighter ones for long figures, then cache reads drop out.
        ViewThatFits(in: .horizontal) {
            row(gap: 12, showsCache: true)
            row(gap: 8, showsCache: true)
            row(gap: 8, showsCache: false)
        }
        .lineLimit(1)
        .foregroundStyle(secondary)
    }

    private func row(gap: CGFloat, showsCache: Bool) -> some View {
        // Tight glyph-to-figure pairs, wider gaps between them: each pair reads as one unit.
        HStack(spacing: gap) {
            metric(Image(systemName: "arrow.up"), UsageFormat.tokens(newInput), "New input tokens",
                   help: "New input: \(Self.exact(total.tokens.input)) fresh + \(Self.exact(total.tokens.cacheWrite)) written to cache. Prompts and tool results.")
            metric(Image(systemName: "arrow.down"), UsageFormat.tokens(total.tokens.output), "Output tokens")
            if showsCache {
                metric(CacheGlyph(), UsageFormat.tokens(total.tokens.cacheRead), "Cache read tokens",
                       help: "Cache read: the conversation so far, re-read from cache with each reply.")
            }
            // The dollar sign is the glyph; a "+" says some replies had no known price.
            Text(UsageFormat.cost(total.cost) + (total.unpriced > 0 ? "+" : ""))
                .font(Theme.font(10, .semibold).monospacedDigit())
                .help(total.unpriced > 0
                      ? "Cost at API prices, subagents included. \(total.unpriced) replies from a model without a known price are left out."
                      : "Cost at API prices, subagents included.")
                .accessibilityLabel("Cost \(UsageFormat.cost(total.cost))")
        }
        .fixedSize()
    }

    private var newInput: Int { total.tokens.input + total.tokens.cacheWrite }

    private static func exact(_ count: Int) -> String { count.formatted(.number) }

    private func metric(_ glyph: some View, _ value: String, _ name: String, help: String? = nil) -> some View {
        HStack(spacing: 3) {
            glyph.font(.system(size: 8, weight: .bold)).accessibilityHidden(true)
            Text(value).font(Theme.font(10).monospacedDigit())
        }
        .help(help ?? name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(value)")
    }
}

/// A cache read: a database cylinder with a small "r" set low at its right, like a subscript.
private struct CacheGlyph: View {
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Image(systemName: "cylinder")
            Text("r").font(.system(size: 7, weight: .heavy, design: .rounded)).baselineOffset(-1.5)
        }
    }
}

/// The session's live subagents under its summary: kind, task, what it runs now, how long it has run.
/// Collapsed cards list three and count the rest; expanded cards list all, with each one's cost.
private struct SubagentList: View {
    let subagents: [Subagent]
    let now: Date
    let secondary: AnyShapeStyle
    let showsAll: Bool
    let usage: [String: UsageTotals]

    private static let collapsedLimit = 3

    var body: some View {
        let shown = showsAll ? subagents : Array(subagents.prefix(Self.collapsedLimit))
        VStack(alignment: .leading, spacing: 4) {
            ForEach(shown) { row($0).transition(.opacity) }
            if shown.count < subagents.count {
                Text("+\(subagents.count - shown.count) more").font(Theme.font(10, .regular)).foregroundStyle(secondary)
            }
        }
        .padding(.leading, 52) // lines up with the text column, past the cat tile
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(subagents.count) subagent\(subagents.count == 1 ? "" : "s")")
    }

    private func row(_ subagent: Subagent) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(subagent.tool == nil ? AnyShapeStyle(secondary) : AnyShapeStyle(Theme.blue))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(subagent.typeLabel).font(Theme.font(11, .semibold)).lineLimit(1).fixedSize()
            if let description = subagent.description {
                Text(description).font(Theme.font(11, .regular)).foregroundStyle(secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Text(subagent.tool ?? "Thinking").font(Theme.font(10, .regular)).foregroundStyle(secondary).lineLimit(1).fixedSize()
            if showsAll, let cost = usage[subagent.id], cost.replies > 0 {
                Text(UsageFormat.cost(cost.cost)).font(Theme.font(10).monospacedDigit()).foregroundStyle(secondary).fixedSize()
            }
            Text(ElapsedFormat.short(from: subagent.startedAt, to: now))
                .font(Theme.font(10).monospacedDigit()).foregroundStyle(secondary).fixedSize()
        }
        .accessibilityElement(children: .combine)
        .help(subagent.description.map { "\(subagent.typeLabel): \($0)" } ?? subagent.typeLabel)
    }
}

/// The mode the session runs in, when it isn't Manual: symbol and name, outlined like the agent label beside it.
/// Bypass gets a red symbol on calm tiles, since nothing asks before it acts.
struct ModeMark: View {
    let mode: PermissionMode
    var onLoudTile = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(mode.isUnguarded && !onLoudTile ? AnyShapeStyle(Theme.red) : AnyShapeStyle(.primary))
            Text(mode.label).font(Theme.font(10, .semibold)).lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .overlay(Capsule().strokeBorder(lineWidth: 1).opacity(0.35))
        .opacity(0.8)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mode: \(mode.label)")
    }

    private var symbol: String {
        switch mode {
        case .manual: "hand.raised"
        case .acceptEdits: "pencil"
        case .plan: "list.bullet"
        case .auto: "bolt.fill"
        case .dontAsk: "hand.raised.slash"
        case .bypassPermissions: "exclamationmark.shield.fill"
        case .other: "slider.horizontal.3"
        }
    }

    private var help: String {
        switch mode {
        case .manual: "Asks before edits and commands."
        case .acceptEdits: "Edits files without asking; still asks before commands."
        case .plan: "Plans only: reads and proposes, doesn't change anything."
        case .auto: "Decides for itself which actions need your OK."
        case .dontAsk: "Never asks; anything not already allowed is refused."
        case .bypassPermissions: "Skips every permission check."
        case .other(let raw): "Mode reported by the agent: \(raw)."
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

