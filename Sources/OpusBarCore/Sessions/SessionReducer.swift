import Foundation
import OpusBarWire

/// The session state machine. Pure: same input, same output, no side effects.
public enum SessionReducer {
    /// Notification types that mean Claude is blocked on the user.
    static let needsYouNotifications: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]

    public static func reduce(_ state: SessionsState, _ event: WireEvent, now: Date) -> SessionsState {
        var state = state
        let e = event.e

        // SessionEnd always wins, even if it arrives out of order.
        if e.event == .sessionEnd {
            state.byId[e.sessionId] = nil
            return state
        }

        var session = state.byId[e.sessionId]
            ?? Session(id: e.sessionId, agent: event.agent ?? .claude, cwd: e.cwd ?? "", startedAt: now)
        // Async hooks can arrive out of order; drop anything older than what we have applied.
        guard event.ts >= session.lastEventTs else { return state }

        session.lastEventTs = event.ts
        session.lastEventAt = now
        if let agent = event.agent { session.agent = agent }
        session.isDiscovered = false
        if let pid = event.pid { session.pid = pid }
        if let term = event.term { session.term = term }
        if let cwd = e.cwd, !cwd.isEmpty, cwd != session.cwd {
            session.cwd = cwd
            session.projectName = Session.projectName(for: cwd)
        }

        switch e.event {
        case .sessionStart:
            session.transition(to: .idle, detail: nil, now: now)
            session.turnStartedAt = nil
            session.subagents = 0
        case .userPromptSubmit:
            session.transition(to: .thinking, detail: nil, now: now)
            session.turnStartedAt = now
        case .preToolUse:
            session.transition(to: .working, detail: e.toolName, now: now)
        case .postToolUse, .postToolUseFailure:
            session.transition(to: .thinking, detail: nil, now: now)
        case .permissionRequest:
            session.transition(to: .needsAttention, detail: allowText(tool: e.toolName), now: now)
        case .notification:
            if let type = e.notificationType, needsYouNotifications.contains(type) {
                // A PermissionRequest usually came first with a better detail; keep it.
                let detail = session.state == .needsAttention && session.detail != nil
                    ? session.detail
                    : notificationText(type: type)
                session.transition(to: .needsAttention, detail: detail, now: now)
            }
        case .subagentStart:
            session.subagents += 1
        case .subagentStop:
            session.subagents = max(0, session.subagents - 1)
        case .stop:
            session.transition(to: .done, detail: nil, now: now)
            session.subagents = 0
            session.turnStartedAt = nil
        case .stopFailure:
            session.transition(to: .error, detail: "API error", now: now)
            session.turnStartedAt = nil
        case .sessionEnd, .unknown:
            break
        }

        state.byId[session.id] = session
        return state
    }

    /// The user has seen these done sessions (the menu was open): Done turns back to Idle, so the
    /// menu bar ✓ and the green card clear. Sessions that finished after `seenAt` keep their Done.
    public static func acknowledgeDone(_ state: SessionsState, seenAt: Date, now: Date) -> SessionsState {
        var state = state
        for (id, session) in state.byId where session.state == .done && session.stateSince <= seenAt {
            var session = session
            session.transition(to: .idle, detail: nil, now: now)
            state.byId[id] = session
        }
        return state
    }

    static func allowText(tool: String?) -> String {
        tool.map { "Allow \($0)?" } ?? "Waiting for permission"
    }

    static func notificationText(type: String) -> String {
        switch type {
        case "permission_prompt": "Waiting for permission"
        case "agent_needs_input": "Needs your input"
        default: "Has a question"
        }
    }
}
