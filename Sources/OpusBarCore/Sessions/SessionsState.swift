import Foundation

public struct SessionsState: Equatable, Sendable {
    public var byId: [String: Session]

    public init(byId: [String: Session] = [:]) {
        self.byId = byId
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
