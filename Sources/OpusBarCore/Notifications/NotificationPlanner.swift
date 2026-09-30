import Foundation

/// Which notification toggles are on. A value copy of the user's Preferences.
public struct NotificationRules: Equatable, Sendable {
    public var needsYou: Bool
    public var error: Bool
    public var done: Bool

    public init(needsYou: Bool, error: Bool, done: Bool) {
        self.needsYou = needsYou
        self.error = error
        self.done = done
    }
}

/// One macOS notification to post. `sessionId` doubles as its identifier, so a newer one for the
/// same session replaces the older instead of piling up.
public struct SessionNotice: Equatable, Sendable {
    public let sessionId: String
    public let state: SessionState
    public let title: String
    /// The agent, and the session's own name when it has one. On a line of its own, so the banner's
    /// text is as tall as the cat thumbnail macOS puts at its bottom right.
    public var subtitle: String = ""
    public let body: String
    /// Notification Center stacks notices with the same thread: one stack per project folder.
    public var thread: String = ""
}

/// Decides notifications from a before/after pair of session states. Pure, like the reducer.
public enum NotificationPlanner {
    public struct Plan: Equatable, Sendable {
        public var post: [SessionNotice] = []
        /// Sessions whose delivered notification is stale: they left the state it announced, or are gone.
        public var clear: [String] = []
    }

    public static func plan(old: SessionsState, new: SessionsState, rules: NotificationRules) -> Plan {
        var plan = Plan()
        for session in new.byId.values.sorted(by: { $0.id < $1.id }) {
            // Discovered rows have no live state; they never notify.
            guard !session.isDiscovered else { continue }
            let before = old.byId[session.id]
            let entered = before?.state != session.state
            if entered, before.map(isAnnounced) == true { plan.clear.append(session.id) }
            guard entered, let notice = notice(for: session, rules: rules) else { continue }
            plan.post.append(notice)
        }
        for id in old.byId.keys.sorted() where new.byId[id] == nil && isAnnounced(old.byId[id]!) {
            plan.clear.append(id)
        }
        return plan
    }

    /// A delivered notification goes stale once its session leaves the announced state or ends,
    /// so Notification Center never shows a session that no longer needs you or no longer exists.
    private static func isAnnounced(_ session: Session) -> Bool {
        session.state == .needsAttention || session.state == .error || session.state == .done
    }

    /// Reads like the card it came from: the project and what happened lead the title, the agent follows
    /// in the subtitle and the detail in the body ("quant needs you" / "Claude Code" / "Allow Bash?"). The
    /// subtitle always names the agent, so a project named like the app still reads as a session.
    static func notice(for session: Session, rules: NotificationRules) -> SessionNotice? {
        let name = session.projectName
        let (title, detail): (String, String)
        switch session.state {
        case .needsAttention where rules.needsYou: (title, detail) = ("\(name) needs you", session.detail ?? "Waiting for you")
        case .error where rules.error: (title, detail) = ("\(name) hit an error", session.detail ?? "Stopped with an error")
        case .done where rules.done: (title, detail) = ("\(name) is done", "Finished its turn")
        default: return nil
        }
        // A session the user named: name it too, so the notice says which one.
        let subtitle = [session.agent.displayName, session.distinctTitle].compactMap { $0 }.joined(separator: " · ")
        return SessionNotice(sessionId: session.id, state: session.state, title: title, subtitle: subtitle, body: detail,
                             thread: session.cwd.isEmpty ? session.id : session.cwd)
    }
}
