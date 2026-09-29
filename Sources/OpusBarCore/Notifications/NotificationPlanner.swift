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
    public let body: String
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

    /// The agent leads the title and the project leads the body, so a project named like the app
    /// ("OpusBar needs you") can't be mistaken for the app itself.
    static func notice(for session: Session, rules: NotificationRules) -> SessionNotice? {
        let name = session.projectName
        let agent = session.agent.displayName
        switch session.state {
        case .needsAttention where rules.needsYou:
            return SessionNotice(sessionId: session.id, state: .needsAttention, title: "\(agent) needs you",
                                 body: "\(name): \(session.detail ?? "Waiting for you")")
        case .error where rules.error:
            return SessionNotice(sessionId: session.id, state: .error, title: "\(agent) hit an error",
                                 body: "\(name): \(session.detail ?? "Stopped with an error")")
        case .done where rules.done:
            return SessionNotice(sessionId: session.id, state: .done, title: "\(agent) is done",
                                 body: "\(name): Finished its turn")
        default:
            return nil
        }
    }
}
