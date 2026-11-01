import Foundation

/// Turns a session into the steps that bring it forward. Pure: no side effects, so the order is tested.
public enum SessionFocusPlanner {
    /// Most exact step first, `activateApp` last. A session with no host app gets `openMenu` only.
    public static func plan(_ session: Session) -> [FocusStep] {
        let tmux = tmuxStep(session).map { [$0] } ?? []
        guard let appPath = session.host?.appPath, !appPath.isEmpty else { return tmux + [.openMenu] }
        return tmux + exactSteps(session, appPath: appPath) + [.raiseWindow(appPath: appPath, needles: WindowNeedles(session))]
            + lateSteps(session, appPath: appPath) + [.activateApp(appPath: appPath)]
    }

    /// The hook saw `$TMUX`, or discovery found a tty with no app above it (the tmux server is launchd's child).
    private static func tmuxStep(_ session: Session) -> FocusStep? {
        guard let paneTty = TerminalScript.safeTty(session.host?.tty) else { return nil }
        if let server = TmuxClientPicker.server(fromTmuxEnv: session.term?.tmux) {
            return .tmuxPane(paneTty: paneTty, socket: server.socket, serverPid: server.pid)
        }
        guard session.host?.appPath == nil else { return nil }
        return .tmuxPane(paneTty: paneTty, socket: nil, serverPid: nil)
    }

    /// The host's own routes to the tab, tried before the app as a whole.
    private static func exactSteps(_ session: Session, appPath: String) -> [FocusStep] {
        switch KnownHost.of(session) {
        case .orca:
            var steps: [FocusStep] = []
            if let handle = session.term?.orcaTerminalHandle, OrcaTerminalPicker.isValidHandle(handle) {
                steps.append(.orcaSwitch(handle: handle, appPath: appPath))
            }
            if !session.cwd.isEmpty { steps.append(.orcaFind(cwd: session.cwd, agent: session.agent, appPath: appPath)) }
            return steps
        case .iterm:
            var steps: [FocusStep] = []
            if let id = session.term?.itermSessionId, TerminalScript.itermRevealURL(sessionId: id) != nil {
                steps.append(.itermReveal(sessionId: id, appPath: appPath))
            }
            if let tty = TerminalScript.safeTty(session.host?.tty) { steps.append(.scriptTab(app: .iterm, tty: tty)) }
            return steps
        case .ghostty:
            var steps: [FocusStep] = []
            if let tty = TerminalScript.safeTty(session.host?.tty) { steps.append(.scriptTab(app: .ghostty, tty: tty)) }
            if TerminalScript.focusByCwd(.ghostty, cwd: session.cwd) != nil { steps.append(.scriptCwd(app: .ghostty, cwd: session.cwd)) }
            return steps
        case .terminalApp:
            guard let tty = TerminalScript.safeTty(session.host?.tty) else { return [] }
            return [.scriptTab(app: .terminalApp, tty: tty)]
        case .vscodeFamily, nil:
            return []
        }
    }

    /// Routes with a side effect, tried only after the window raise found nothing.
    private static func lateSteps(_ session: Session, appPath: String) -> [FocusStep] {
        // Opening the folder focuses the window that has it; with the folder not open, the editor opens a window.
        guard KnownHost.of(session) == .vscodeFamily, !session.cwd.isEmpty else { return [] }
        return [.vscodeWindow(appPath: appPath, folder: session.cwd)]
    }
}
