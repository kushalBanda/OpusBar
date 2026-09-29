import Foundation

/// The coding agents OpusBar tracks. Events without an agent come from Claude Code (the M1 hook setup).
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claude, codex, pi, omp

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .pi: "pi"
        case .omp: "OMP"
        }
    }

    /// Reads `--agent <name>` or `--agent=<name>` from the hook's arguments. Unknown names give nil.
    public static func fromArguments(_ arguments: [String]) -> AgentKind? {
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--agent=") {
                return AgentKind(rawValue: String(argument.dropFirst(8)).lowercased())
            }
            if argument == "--agent", index + 1 < arguments.count {
                return AgentKind(rawValue: arguments[index + 1].lowercased())
            }
        }
        return nil
    }
}
