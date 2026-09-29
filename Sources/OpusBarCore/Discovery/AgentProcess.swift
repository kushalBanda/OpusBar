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

    public init(pid: Int32, ppid: Int32 = 1, startedAt: Date? = nil, executablePath: String = "",
                arguments: [String], cwd: String? = nil) {
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
