import Foundation

/// Removes sessions that are over. Pure, like the reducer.
public enum SessionPruner {
    public static func prune(
        _ state: SessionsState,
        now: Date,
        finishedTTL: TimeInterval,
        isAlive: (Int32) -> Bool
    ) -> SessionsState {
        var state = state
        state.byId = state.byId.filter { _, session in
            // The Claude process is gone: the session cannot produce more events.
            if let pid = session.pid, !isAlive(pid) { return false }
            // Finished sessions linger for the user's TTL, then leave.
            let finished = session.state == .done || session.state == .error
            return !(finished && now.timeIntervalSince(session.stateSince) >= finishedTTL)
        }
        return state
    }
}
