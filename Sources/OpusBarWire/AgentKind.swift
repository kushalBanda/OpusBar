import Foundation

/// The coding agents OpusBar tracks. Events without an agent come from Claude Code (the M1 hook setup).
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claude, codex

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// Reads `--agent <name>` or `--agent=<name>` from the hook's arguments. Unknown names give nil.
    public static func fromArguments(_ arguments: [String]) -> AgentKind? {
        agentArgument(arguments).flatMap { AgentKind(rawValue: $0.lowercased()) }
    }

    /// True when `--agent` names an agent OpusBar doesn't track (e.g. a leftover pi/OMP extension).
    public static func namesUnknownAgent(_ arguments: [String]) -> Bool {
        agentArgument(arguments) != nil && fromArguments(arguments) == nil
    }

    static func agentArgument(_ arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--agent=") {
                return String(argument.dropFirst(8))
            }
            if argument == "--agent", index + 1 < arguments.count {
                return arguments[index + 1]
            }
        }
        return nil
    }
}
