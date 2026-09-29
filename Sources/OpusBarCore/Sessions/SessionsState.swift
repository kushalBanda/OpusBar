import Foundation

public struct SessionsState: Equatable, Sendable {
    public var byId: [String: Session]
    /// Hook time of each recent SessionEnd, so an event sent before it but delivered after it
    /// can't bring the row back. Oldest entries drop past `endedKept`.
    public var endedAt: [String: Int64]
    static let endedKept = 256

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
