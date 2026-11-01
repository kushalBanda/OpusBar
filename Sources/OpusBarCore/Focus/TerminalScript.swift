import Foundation

/// A terminal app driven by AppleScript, matched by the session's tty.
public enum ScriptableTerminal: Hashable, Sendable {
    case terminalApp, iterm, ghostty

    public var bundleId: String {
        switch self {
        case .terminalApp: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        }
    }
}

/// The AppleScript text for a tab step and how to read what `osascript` answered. Pure, so the script
/// and the outcome rules are tested without running a terminal.
public enum TerminalScript {
    /// Accepts `ttys004` or `/dev/ttys004` and gives `/dev/ttys004`. Anything else gives nil, so nothing
    /// but a plain device path is ever put into a script.
    public static func safeTty(_ tty: String?) -> String? {
        guard let tty else { return nil }
        let name = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        guard name.hasPrefix("ttys"), name.count > 4, name.dropFirst(4).allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        return "/dev/" + name
    }

    /// Selects the tab whose tty matches, puts its window in front and activates the app. Prints
    /// `focused`, or `none` when no tab has that tty. Talks to the app by bundle id, so a renamed app works.
    public static func focusTab(_ app: ScriptableTerminal, tty: String) -> String? {
        guard let tty = safeTty(tty) else { return nil }
        switch app {
        case .terminalApp:
            return """
            tell application id "\(app.bundleId)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return "focused"
                        end if
                    end repeat
                end repeat
            end tell
            return "none"
            """
        case .iterm:
            // iTerm2 has split panes: the session is the pane, so it is selected after its tab and window.
            return """
            tell application id "\(app.bundleId)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return "focused"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "none"
            """
        case .ghostty:
            // `tty` is in Ghostty 1.4 and later. On 1.3 the script doesn't compile, which counts as not found,
            // and the folder step runs next. `focus` selects the split, its tab and its window.
            return """
            tell application id "\(app.bundleId)"
                set matches to every terminal whose tty is "\(tty)"
                if (count of matches) > 0 then
                    focus item 1 of matches
                    activate
                    return "focused"
                end if
            end tell
            return "none"
            """
        }
    }

    /// Ghostty 1.3 has no `tty`, only each terminal's folder. Only one terminal in the session's folder
    /// counts: with two, picking one could land on the wrong session, so the window raise runs instead.
    public static func focusByCwd(_ app: ScriptableTerminal, cwd: String) -> String? {
        guard app == .ghostty, let folder = literal(cwd), cwd.hasPrefix("/") else { return nil }
        return """
        tell application id "\(app.bundleId)"
            set matches to every terminal whose working directory is \(folder)
            if (count of matches) is 1 then
                focus item 1 of matches
                activate
                return "focused"
            end if
        end tell
        return "none"
        """
    }

    /// A quoted AppleScript string. Backslashes and quotes are escaped; any control character gives nil.
    static func literal(_ text: String) -> String? {
        guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// iTerm2's documented reveal URL. It takes the whole `ITERM_SESSION_ID` (`w0t0p0:<GUID>`), finds the
    /// session in any window, and needs no permission. Any other shape gives nil.
    public static func itermRevealURL(sessionId: String?) -> URL? {
        guard let sessionId, isItermSessionId(sessionId) else { return nil }
        return URL(string: "iterm2:reveal?sessionid=" + sessionId)
    }

    static func isItermSessionId(_ id: String) -> Bool {
        id.range(of: #"^w\d+t\d+p\d+:[0-9A-Fa-f-]{8,64}$"#, options: .regularExpression) != nil
    }

    /// `osascript` exit status and output to an outcome. -1743 is "not authorized to send Apple events"
    /// (Automation is off for this pair of apps); every other failure counts as not found.
    public static func outcome(status: Int32, stdout: String, stderr: String) -> FocusOutcome {
        if status == 0 { return stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "focused" ? .focused : .notFound }
        return stderr.contains("-1743") ? .denied : .notFound
    }
}
