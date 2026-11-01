import Foundation

/// Runs a session's focus plan. Holds the fallback rules, so they are tested without a Mac UI.
public enum FocusSequence {
    /// Tries the planned steps in order and stops at the first `.focused`. `.denied` and `.notFound`
    /// go on to the next step. Returns the step that focused, or nil if none did.
    @discardableResult
    public static func run(_ session: Session, using performer: FocusPerforming) async -> FocusStep? {
        await run(SessionFocusPlanner.plan(session), using: performer, session: session)
    }

    @discardableResult
    static func run(_ steps: [FocusStep], using performer: FocusPerforming, session: Session? = nil) async -> FocusStep? {
        for step in steps {
            if case let .tmuxPane(paneTty, socket, serverPid) = step {
                // The pane is now on screen in its client; what is left is to bring that client's terminal forward.
                guard let session, let host = await performer.tmuxHost(paneTty: paneTty, socket: socket, serverPid: serverPid)
                else { continue }
                var outer = session
                outer.host = host
                outer.term = nil // the pane's environment names the terminal tmux started in, not the client's
                if let focused = await run(SessionFocusPlanner.plan(outer), using: performer) { return focused }
                continue
            }
            if await performer.perform(step) == .focused { return step }
        }
        return nil
    }
}
