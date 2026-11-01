import Foundation
import OpusBarWire

/// One way to bring a session in front of the user. `SessionFocusPlanner` orders them, most exact first;
/// `FocusSequence` tries them until one works.
public enum FocusStep: Hashable, Sendable {
    /// tmux: switch the client to the session's pane, then plan again for the terminal app that shows the client.
    /// `socket` and `serverPid` come from `$TMUX`; without them the default server is asked.
    case tmuxPane(paneTty: String, socket: String?, serverPid: Int32?)
    /// Orca: switch to the tab the hook named (`ORCA_TERMINAL_HANDLE`), then bring Orca forward.
    case orcaSwitch(handle: String, appPath: String)
    /// Orca: find the agent's tab by folder (`orca terminal list`), switch to it, bring Orca forward.
    case orcaFind(cwd: String, agent: AgentKind, appPath: String)
    /// AppleScript: select the tab whose tty matches, put its window in front. Needs Automation.
    case itermReveal(sessionId: String, appPath: String) // `iterm2:reveal?sessionid=`, no permission
    case scriptTab(app: ScriptableTerminal, tty: String)
    case scriptCwd(app: ScriptableTerminal, cwd: String) // the one terminal open in the session's folder
    /// Accessibility: raise the host window whose title names the session (`WindowPicker`). Asks once.
    case raiseWindow(appPath: String, needles: WindowNeedles)
    /// VS Code family: open the session's folder in the editor, which brings its window forward.
    case vscodeWindow(appPath: String, folder: String)
    /// Bring the app that hosts the session forward. Works for any app, needs no permission.
    case activateApp(appPath: String)
    /// No host app is known: show OpusBar's own dropdown.
    case openMenu
}

/// What one step did.
public enum FocusOutcome: Equatable, Sendable {
    case focused
    /// The target (tab, window, app) was not there.
    case notFound
    /// macOS refused (Automation or Accessibility not granted).
    case denied
}

/// Carries out focus steps. The app's runner does it with AppKit; tests use a fake.
public protocol FocusPerforming: Sendable {
    func perform(_ step: FocusStep) async -> FocusOutcome
    /// For `.tmuxPane`: switches the client to the pane and gives the app and tty that show it, or nil.
    func tmuxHost(paneTty: String, socket: String?, serverPid: Int32?) async -> SessionHost?
}
