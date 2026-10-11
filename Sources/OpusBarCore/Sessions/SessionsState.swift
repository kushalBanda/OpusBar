import Foundation

public struct SessionsState: Equatable, Sendable {
    public var byId: [String: Session]
    /// Hook time of each recent SessionEnd, so an event sent before it but delivered after it
    /// can't bring the row back. Oldest entries drop past `endedKept`.
    public var endedAt: [String: Int64]
    static let endedKept = 256
    /// The mode each agent process had when its last session ended. `/clear` ends one session and starts
    /// the next in the same process, whose SessionStart carries no mode. Used up by that next session;
    /// capped like `endedAt` for processes that quit instead.
    public var endedModeByPid: [Int32: PermissionMode] = [:]

    public init(byId: [String: Session] = [:], endedAt: [String: Int64] = [:]) {
        self.byId = byId
        self.endedAt = endedAt
    }

    /// Most urgent first; within the same state, the one waiting longest first.
    public var sorted: [Session] {
        byId.values.sorted { a, b in
            if a.state.loudness != b.state.loudness { return a.state.loudness > b.state.loudness }
            if a.stateSince != b.stateSince { return a.stateSince < b.stateSince }
            return a.id < b.id
        }
    }
}
