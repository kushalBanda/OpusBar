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
            if let ended = state.byId[e.sessionId], let pid = ended.pid ?? event.pid, let mode = ended.permissionMode {
                state.endedModeByPid[pid] = mode
                if state.endedModeByPid.count > SessionsState.endedKept, let any = state.endedModeByPid.keys.first(where: { $0 != pid }) {
                    state.endedModeByPid[any] = nil
                }
            }
            state.byId[e.sessionId] = nil
            state.endedAt[e.sessionId] = max(state.endedAt[e.sessionId] ?? .min, event.ts)
            if state.endedAt.count > SessionsState.endedKept,
               let oldest = state.endedAt.min(by: { $0.value < $1.value })?.key {
                state.endedAt[oldest] = nil
            }
            return state
        }
        // Sent before this session ended, delivered after.
        if let ended = state.endedAt[e.sessionId], event.ts <= ended { return state }

        var session = state.byId[e.sessionId] ?? newSession(for: event, in: state, now: now)
        if state.byId[e.sessionId] == nil, let pid = event.pid { state.endedModeByPid[pid] = nil }
        // Async hooks can arrive out of order; drop anything older than what we have applied.
        guard event.ts >= session.lastEventTs else { return state }

        session.lastEventTs = event.ts
        session.lastEventAt = now
        if let agent = event.agent { session.agent = agent }
        session.isDiscovered = false
        if let pid = event.pid { session.pid = pid }
        if let term = event.term { session.term = term }
        if let mode = PermissionMode(raw: e.permissionMode) { session.permissionMode = mode }
        if let path = e.transcriptPath, !path.isEmpty { session.transcriptPath = path }
        if let signIn = event.signIn { session.signIn = signIn }

        // Inside a subagent: its own row moves, the parent's state doesn't. A background subagent keeps
        // working after the parent's Stop, and must not turn a finished session back to working.
        // A permission prompt still blocks on the user, so it falls through to the parent below.
        if let agentId = e.agentId, !agentId.isEmpty, e.event != .subagentStart, e.event != .subagentStop {
            var subagent = session.subagents.first { $0.id == agentId }
                ?? Subagent(id: agentId, type: e.agentType ?? "", startedAt: now)
            subagent.lastEventAt = now
            switch e.event {
            case .preToolUse: subagent.tool = e.toolName
            case .postToolUse, .postToolUseFailure: subagent.tool = nil
            default: break
            }
            session.upsert(subagent)
            if e.event != .permissionRequest {
                state.byId[session.id] = session
                return state
            }
        }
        if let cwd = e.cwd, !cwd.isEmpty, cwd != session.cwd {
            session.cwd = cwd
            session.projectName = Session.projectName(for: cwd)
        }

        switch e.event {
        case .sessionStart:
            session.transition(to: .idle, detail: nil, now: now)
            session.turnStartedAt = nil
            session.subagents = []
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
            let id = e.agentId.flatMap { $0.isEmpty ? nil : $0 } ?? "start:\(event.ts)"
            var subagent = session.subagents.first { $0.id == id } ?? Subagent(id: id, type: e.agentType ?? "", startedAt: now)
            if let type = e.agentType, !type.isEmpty { subagent.type = type }
            subagent.lastEventAt = now
            session.upsert(subagent)
        case .subagentStop:
            if let id = e.agentId, let index = session.subagents.firstIndex(where: { $0.id == id }) {
                session.subagents.remove(at: index)
            } else if !session.subagents.isEmpty {
                session.subagents.removeFirst() // a stop without an id ends the oldest
            }
        case .stop:
            // Subagents stay: background ones run on after the turn and report their own stop.
            session.transition(to: .done, detail: nil, now: now)
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

    /// `/clear` and `/resume` start a new session id in the same process, and the mode carries over;
    /// SessionStart doesn't report it, so take it from the process's previous session (ended, or the
    /// discovered row it is replacing).
    static func newSession(for event: WireEvent, in state: SessionsState, now: Date) -> Session {
        var session = Session(id: event.e.sessionId, agent: event.agent ?? .claude, cwd: event.e.cwd ?? "", startedAt: now)
        if let pid = event.pid {
            session.permissionMode = state.endedModeByPid[pid]
                ?? state.byId.values.first { $0.pid == pid && $0.permissionMode != nil }?.permissionMode
        }
        return session
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
