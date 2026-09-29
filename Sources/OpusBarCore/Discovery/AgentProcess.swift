import Foundation
import OpusBarWire

/// One running process as discovery sees it. `cwd` is filled only for agent processes.
public struct AgentProcess: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    public var startedAt: Date?
    public var executablePath: String
    /// argv only. The environment that follows argv in the kernel buffer is never parsed.
    public var arguments: [String]
    public var cwd: String?
    /// Controlling terminal, e.g. `ttys013`; nil for processes without one.
    public var tty: String?

    public init(pid: Int32, ppid: Int32 = 1, startedAt: Date? = nil, executablePath: String = "",
                arguments: [String], cwd: String? = nil, tty: String? = nil) {
        self.tty = tty
        self.pid = pid
        self.ppid = ppid
        self.startedAt = startedAt
        self.executablePath = executablePath
        self.arguments = arguments
        self.cwd = cwd
    }

    /// Basename of argv[0]. Native Claude runs from `…/claude/versions/<version>`, so the path alone can't identify it.
    var argv0Basename: String {
        URL(fileURLWithPath: arguments.first ?? executablePath).lastPathComponent.lowercased()
    }

    var commandLine: String { arguments.isEmpty ? executablePath : arguments.joined(separator: " ") }
}

/// Where a session runs: the app hosting its terminal (Terminal, iTerm, Terax, VS Code…) and its tty.
public struct SessionHost: Equatable, Sendable {
    public var appName: String?
    public var appPath: String?
    public var tty: String?

    /// Walks parent processes from `pid` to the first one running inside an `.app` bundle.
    /// Uses the outermost bundle, so editor helpers (`Code Helper.app` inside `Visual Studio Code.app`)
    /// resolve to the editor. tmux and ssh sessions end at launchd with no app: tty only.
    public static func resolve(pid: Int32, processes: [Int32: AgentProcess], maxDepth: Int = 16) -> SessionHost? {
        guard let start = processes[pid] else { return nil }
        var current = start.ppid
        for _ in 0..<maxDepth {
            guard current > 1, let process = processes[current] else { break }
            if let bundle = outermostAppBundle(in: process.executablePath) {
                return SessionHost(appName: (bundle as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""),
                                   appPath: bundle, tty: start.tty)
            }
            current = process.ppid
        }
        return start.tty.map { SessionHost(appName: nil, appPath: nil, tty: $0) }
    }

    static func outermostAppBundle(in path: String) -> String? {
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            components.append(String(component))
            if component.hasSuffix(".app") { return components.joined(separator: "/") }
        }
        return nil
    }

    /// "Terax · ttys013", "ttys004", or nil.
    public var label: String? {
        let parts = [appName, tty].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
