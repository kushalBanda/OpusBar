import Foundation
import OpusBarWire

/// Decides which processes are agent sessions. Helpers, one-shot commands and app servers are skipped.
public enum AgentProcessClassifier {
    static let claudeDesktopPath = "application support/claude/claude-code/claude"
    static let trustedCodexAppPaths: Set<String> = [
        "/applications/codex.app/contents/resources/codex",
        "/applications/chatgpt.app/contents/resources/codex",
    ]

    /// Claude modes that run the CLI binary without being a chat session.
    static let claudeNonSessionFlags: Set<String> = ["--chrome-native-host"]
    static let claudeNonSessionCommands: Set<String> = ["mcp", "config", "update", "doctor", "install", "setup-token", "plugin", "migrate-installer"]

    public static func kind(of process: AgentProcess) -> AgentKind? {
        let command = process.commandLine.lowercased()
        let flags = process.arguments.dropFirst().map { $0.lowercased() }
        if flags.contains("--help") || flags.contains("--version") || flags.contains("-v") && flags.count == 1 {
            return nil
        }
        if let dialect = piDialect(of: process) {
            return command.contains("--smoke-test") || command.contains("__omp_worker_") ? nil : dialect
        }
        switch process.argv0Basename {
        case "codex":
            guard !flags.contains("app-server"), !flags.contains("mcp-server") else { return nil }
            guard command.contains(".app/") else { return .codex }
            let executable = (process.arguments.first ?? process.executablePath).lowercased()
            return trustedCodexAppPaths.contains(executable) ? .codex : nil
        case "claude":
            guard !command.contains("claude-code-acp"),
                  !flags.contains(where: claudeNonSessionFlags.contains),
                  !(flags.first.map(claudeNonSessionCommands.contains) ?? false)
            else { return nil }
            return !command.contains(".app/") || command.contains(claudeDesktopPath) ? .claude : nil
        case "disclaimer":
            // Claude desktop launches the CLI through a `disclaimer` wrapper.
            return command.contains("claude") ? .claude : nil
        default:
            return command.contains(claudeDesktopPath) ? .claude : nil
        }
    }

    /// `pi` / `omp` by process title, or OMP run through bun (`bun … omp`).
    static func piDialect(of process: AgentProcess) -> AgentKind? {
        switch process.argv0Basename {
        case "pi": return .pi
        case "omp": return .omp
        case "bun":
            let hasOMP = process.arguments.dropFirst().contains {
                URL(fileURLWithPath: $0).lastPathComponent.lowercased() == "omp"
            }
            return hasOMP ? .omp : nil
        default: return nil
        }
    }

    /// Agent processes, newest first, at most `limit`. A `disclaimer` wrapper is dropped when its
    /// own `claude` child is also listed, so one session shows once.
    public static func agentProcesses(from all: [AgentProcess], limit: Int = 64) -> [(AgentProcess, AgentKind)] {
        let tagged = all.compactMap { process in kind(of: process).map { (process, $0) } }
        let wrapperPIDs = Set(tagged.filter { $0.0.argv0Basename == "disclaimer" }.map(\.0.pid))
        let wrappedParents = Set(tagged.filter { $0.1 == .claude && $0.0.argv0Basename != "disclaimer" }.map(\.0.ppid))
        return tagged
            .filter { !(wrapperPIDs.contains($0.0.pid) && wrappedParents.contains($0.0.pid)) }
            .sorted { ($0.0.startedAt ?? .distantPast, $0.0.pid) > ($1.0.startedAt ?? .distantPast, $1.0.pid) }
            .prefix(limit)
            .map { $0 }
    }
}
