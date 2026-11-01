import AppKit
import OpusBarCore
import os
import SwiftUI

/// Brings a session forward: a notification click and the row's "Show in" button both land here.
/// Plans the steps with `SessionFocusPlanner` and carries each one out with AppKit.
@MainActor
final class FocusRunner: FocusPerforming {
    nonisolated static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "OpusBar", category: "focus")

    private let store: SessionStore
    private let openMenu: () -> Void

    init(store: SessionStore, openMenu: @escaping () -> Void) {
        self.store = store
        self.openMenu = openMenu
    }

    /// Looks the session up by id. A session that is gone, or the Settings test notice, opens the dropdown.
    func focus(sessionId: String) async {
        guard var session = store.state.byId[sessionId] else { openMenu(); return }
        // A session newer than the last discovery pass has no app yet: find it now, from the process tree.
        if session.host == nil, let pid = session.pid {
            session.host = await Task.detached(priority: .userInitiated) {
                let processes = DarwinProcessLister().processes()
                return SessionHost.resolve(pid: pid, processes: Dictionary(processes.map { ($0.pid, $0) },
                                                                           uniquingKeysWith: { first, _ in first }))
            }.value
        }
        await focus(session)
    }

    func focus(_ session: Session) async {
        let step = await FocusSequence.run(session, using: self)
        Self.log.info("focus \(session.id, privacy: .public): \(step.map { "\($0)" } ?? "nothing focused", privacy: .public)")
    }

    func perform(_ step: FocusStep) async -> FocusOutcome {
        switch step {
        case let .activateApp(appPath):
            // The completion form: the async one hands a non-Sendable NSRunningApplication across actors.
            return await withCheckedContinuation { done in
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: .init()) { _, error in
                    if let error {
                        Self.log.error("activate \(appPath, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    }
                    done.resume(returning: error == nil ? .focused : .notFound)
                }
            }
        case .openMenu:
            openMenu()
            return .focused
        case let .orcaSwitch(handle, appPath):
            return await orcaSwitch(handle: handle, appPath: appPath)
        case let .orcaFind(cwd, agent, appPath):
            guard let list = await Self.run(Self.orcaCLI(appPath), ["terminal", "list", "--json"]), list.status == 0,
                  let handle = OrcaTerminalPicker.handle(fromListJSON: list.output, cwd: cwd, agent: agent)
            else { return .notFound }
            return await orcaSwitch(handle: handle, appPath: appPath)
        case let .itermReveal(sessionId, appPath):
            return await itermReveal(sessionId, appPath: appPath)
        case let .scriptTab(app, tty):
            return await scriptTab(app, tty: tty)
        case let .scriptCwd(app, cwd):
            return await scriptCwd(app, cwd: cwd)
        case .tmuxPane:
            return .notFound // `FocusSequence` resolves it through `tmuxHost`
        case let .raiseWindow(appPath, needles):
            return await raiseWindow(appPath: appPath, needles: needles)
        case let .vscodeWindow(appPath, folder):
            return await openFolder(Self.repositoryRoot(of: folder), in: appPath)
        }
    }

    /// Asked for at most once per launch: the system prompt is the user's to answer, not ours to repeat.
    private var askedForAccessibility = false

    /// Raises the window whose title names the session. Without Accessibility it asks once and reports
    /// `.denied`, so the click still brings the app forward.
    private func raiseWindow(appPath: String, needles: WindowNeedles) async -> FocusOutcome {
        guard AXIsProcessTrusted() else {
            if !askedForAccessibility {
                askedForAccessibility = true
                // The literal key: the `kAXTrustedCheckOptionPrompt` global trips strict concurrency checks.
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            return .denied
        }
        guard let pid = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: appPath).standardizedFileURL.path })?
            .processIdentifier else { return .notFound }
        let raised = await Task.detached { () -> Bool in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 1) // a hung app must not hold the click
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { return false }
            let titles = windows.map { window -> String in
                var title: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                return title as? String ?? ""
            }
            guard let index = WindowPicker.pick(titles: titles, needles: needles) else { return false }
            AXUIElementSetAttributeValue(windows[index], kAXMainAttribute as CFString, kCFBooleanTrue)
            return AXUIElementPerformAction(windows[index], kAXRaiseAction as CFString) == .success
        }.value
        guard raised else { return .notFound }
        // The raised window is the app's front one; activating the app now shows that window.
        return await perform(.activateApp(appPath: appPath))
    }

    /// The editor focuses the window that already has this folder open.
    /// Hands a link to that app only, so another app that claims the scheme can't take it.
    private func open(_ url: URL, in appPath: String) async -> FocusOutcome {
        await withCheckedContinuation { done in
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: appPath), configuration: .init()) { _, error in
                if let error { Self.log.error("open link failed: \(error.localizedDescription, privacy: .public)") }
                done.resume(returning: error == nil ? .focused : .notFound)
            }
        }
    }

    private func openFolder(_ folder: String, in appPath: String) async -> FocusOutcome {
        await withCheckedContinuation { done in
            NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)],
                                    withApplicationAt: URL(fileURLWithPath: appPath), configuration: .init()) { _, error in
                if let error { Self.log.error("open folder failed: \(error.localizedDescription, privacy: .public)") }
                done.resume(returning: error == nil ? .focused : .notFound)
            }
        }
    }

    /// Editors open a repository at its root. A session in a subfolder would otherwise get a new window
    /// for that subfolder. `.git` is a folder in a clone and a file in a worktree; both count.
    nonisolated static func repositoryRoot(of folder: String) -> String {
        var url = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: ".git").path) { return url.path }
            url.deleteLastPathComponent()
        }
        return folder
    }

    func tmuxHost(paneTty: String, socket: String?, serverPid: Int32?) async -> SessionHost? {
        await Task.detached { () -> SessionHost? in
            let processes = Dictionary(DarwinProcessLister().processes().map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
            guard let tmux = Self.tmuxBinary(serverPid: serverPid, processes: processes) else { return nil }
            let server = socket.map { ["-S", $0] } ?? []
            guard let panes = await Self.run(tmux, server + ["list-panes", "-a", "-F", TmuxClientPicker.panesFormat]),
                  let clients = await Self.run(tmux, server + ["list-clients", "-F", TmuxClientPicker.clientsFormat]),
                  panes.status == 0, clients.status == 0,
                  let pick = TmuxClientPicker.pick(paneTty: paneTty, panes: String(decoding: panes.output, as: UTF8.self),
                                                   clients: String(decoding: clients.output, as: UTF8.self))
            else { return nil }
            // One command: tmux moves the client to the pane's session, window and pane.
            guard let switched = await Self.run(tmux, server + ["switch-client", "-c", pick.clientTty, "-t", pick.paneId]),
                  switched.status == 0 else { return nil }
            Self.log.info("tmux: \(pick.paneId, privacy: .public) shown on \(pick.clientTty, privacy: .public)")
            return SessionHost.resolve(pid: pick.clientPid, processes: processes)
        }.value
    }

    /// The binary that runs the session's server, so a second tmux install never answers for it. Without
    /// `$TMUX` (a discovered session), the usual install places.
    nonisolated private static func tmuxBinary(serverPid: Int32?, processes: [Int32: AgentProcess]) -> URL? {
        let running = serverPid.flatMap { processes[$0]?.executablePath }.map { [$0] } ?? []
        let known = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/opt/local/bin/tmux", "/usr/bin/tmux"]
        return (running + known).first { $0.hasSuffix("/tmux") && FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Only for a running iTerm2: opening the URL would otherwise launch it with no such session.
    /// The URL selects the session; iTerm2 is activated after it so the window is in front.
    private func itermReveal(_ sessionId: String, appPath: String) async -> FocusOutcome {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: ScriptableTerminal.iterm.bundleId).isEmpty,
              let url = TerminalScript.itermRevealURL(sessionId: sessionId) else { return .notFound }
        guard await open(url, in: appPath) == .focused else { return .notFound }
        return await perform(.activateApp(appPath: appPath))
    }

    private func scriptTab(_ app: ScriptableTerminal, tty: String) async -> FocusOutcome {
        guard let script = TerminalScript.focusTab(app, tty: tty) else { return .notFound }
        return await runScript(script, in: app)
    }

    private func scriptCwd(_ app: ScriptableTerminal, cwd: String) async -> FocusOutcome {
        guard let script = TerminalScript.focusByCwd(app, cwd: cwd) else { return .notFound }
        return await runScript(script, in: app)
    }

    /// Runs only while the terminal is open: `tell application` would launch a closed one, and a closed
    /// terminal has no tab to find. `osascript` runs as OpusBar's child, so macOS asks about OpusBar.
    private func runScript(_ script: String, in app: ScriptableTerminal) async -> FocusOutcome {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId).isEmpty else { return .notFound }
        // The first run may wait on the Automation prompt, so it gets longer than a command line tool.
        guard let result = await Self.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script], timeout: 60)
        else { return .notFound }
        let outcome = TerminalScript.outcome(status: result.status, stdout: String(decoding: result.output, as: UTF8.self),
                                             stderr: result.errors)
        if outcome == .denied { Self.log.notice("Automation for \(app.bundleId, privacy: .public) is off") }
        return outcome
    }

    /// `orca terminal switch` picks the tab but leaves Orca behind other apps, so Orca comes forward after it.
    private func orcaSwitch(handle: String, appPath: String) async -> FocusOutcome {
        guard let result = await Self.run(Self.orcaCLI(appPath), ["terminal", "switch", "--terminal", handle]),
              result.status == 0 else { return .notFound } // a stale handle exits 1 (`terminal_handle_stale`)
        return await perform(.activateApp(appPath: appPath))
    }

    /// Orca ships its command line tool inside the app bundle.
    private static func orcaCLI(_ appPath: String) -> URL {
        URL(fileURLWithPath: appPath).appending(path: "Contents/Resources/bin/orca")
    }

    /// Runs a tool off the main thread with no shell. Gives up after `timeout`, so a hung host can't hold the click.
    nonisolated private static func run(_ tool: URL, _ arguments: [String], timeout: TimeInterval = 5)
        async -> (status: Int32, output: Data, errors: String)? {
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return nil }
        return await Task.detached {
            let process = Process()
            process.executableURL = tool
            process.arguments = arguments
            let pipe = Pipe(), errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            do { try process.run() } catch {
                log.error("\(tool.lastPathComponent, privacy: .public) failed to start: \(error.localizedDescription, privacy: .public)")
                return nil
            }
            let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            // Errors are read on their own thread: a full stderr pipe would block the tool and stdout with it.
            let errors = Task.detached { errorPipe.fileHandleForReading.readDataToEndOfFile() }
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            deadline.cancel()
            return (process.terminationStatus, output, String(decoding: await errors.value, as: UTF8.self))
        }.value
    }
}

/// The row's "Show in" button: brings a session forward. The dropdown sets it from `FocusRunner`.
private struct ShowSessionKey: EnvironmentKey {
    static let defaultValue: @MainActor (Session) -> Void = { _ in }
}

extension EnvironmentValues {
    var showSession: @MainActor (Session) -> Void {
        get { self[ShowSessionKey.self] }
        set { self[ShowSessionKey.self] = newValue }
    }
}
