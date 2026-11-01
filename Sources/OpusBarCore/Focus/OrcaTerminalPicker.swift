import Foundation
import OpusBarWire

/// Picks a session's terminal from `orca terminal list --json`, for sessions whose hook gave no handle
/// (found by discovery, or started before the hook knew `ORCA_TERMINAL_HANDLE`).
public enum OrcaTerminalPicker {
    private struct Reply: Decodable {
        struct Result: Decodable { let terminals: [Terminal] }
        let ok: Bool
        let result: Result?
    }

    private struct Terminal: Decodable {
        let handle: String
        let worktreePath: String?
        let orphaned: Bool?
        let agentIdentity: String?
        let lastOutputAt: Double?
    }

    /// The live terminal running this agent in the worktree that holds `cwd`. The deepest worktree wins
    /// (a session in `repo/sub` belongs to `repo`); between two in one worktree, the latest output wins.
    /// Orphaned terminals and other agents are skipped: no match is better than the wrong tab.
    public static func handle(fromListJSON json: Data, cwd: String, agent: AgentKind) -> String? {
        guard !cwd.isEmpty, let reply = try? JSONDecoder().decode(Reply.self, from: json), reply.ok,
              let terminals = reply.result?.terminals else { return nil }
        let candidates = terminals.filter {
            $0.orphaned != true && $0.agentIdentity == agent.rawValue && isValidHandle($0.handle)
                && $0.worktreePath.map { contains(worktree: $0, cwd: cwd) } == true
        }
        let best = candidates.max { a, b in
            let (depthA, depthB) = (a.worktreePath?.count ?? 0, b.worktreePath?.count ?? 0)
            return depthA != depthB ? depthA < depthB : (a.lastOutputAt ?? 0) < (b.lastOutputAt ?? 0)
        }
        return best?.handle
    }

    /// Orca handles look like `term_<uuid>`. Anything else never reaches the command line, so a value
    /// from the environment can't pass as an option.
    public static func isValidHandle(_ handle: String) -> Bool {
        handle.hasPrefix("term_") && handle.count > 5
            && handle.dropFirst(5).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    private static func contains(worktree: String, cwd: String) -> Bool {
        let root = worktree.hasSuffix("/") ? String(worktree.dropLast()) : worktree
        return cwd == root || cwd.hasPrefix(root + "/")
    }
}
