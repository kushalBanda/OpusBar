/// What the menu bar item shows across all sessions.
public struct Aggregate: Equatable, Sendable {
    /// The loudest state, nil when there are no sessions.
    public var state: SessionState?
    public var needsYouCount: Int
    /// Sessions that are not idle.
    public var activeCount: Int

    public init(state: SessionState?, needsYouCount: Int, activeCount: Int) {
        self.state = state
        self.needsYouCount = needsYouCount
        self.activeCount = activeCount
    }

    public static func of<S: Sequence>(_ sessions: S) -> Aggregate where S.Element == Session {
        var loudest: SessionState?
        var needsYou = 0
        var active = 0
        for session in sessions {
            if loudest.map({ session.state.loudness > $0.loudness }) ?? true { loudest = session.state }
            if session.state == .needsAttention { needsYou += 1 }
            if session.state != .idle { active += 1 }
        }
        return Aggregate(state: loudest, needsYouCount: needsYou, activeCount: active)
    }
}
