import Foundation
import OpusBarWire

/// Pairs live agent processes with their session records.
public enum SessionCorrelator {
    /// Newest process first; each record used once.
    /// - Claude and pi/OMP: same cwd, and the record changed at or after the process started.
    ///   Claude only when a single Claude process runs in that cwd (otherwise the pairing is a guess).
    /// - Codex: first unused rollout with the same cwd.
    public static func match(_ processes: [DiscoveredProcess], records: [SessionRecord]) -> [Int32: SessionRecord] {
        var used = Set<String>()
        var result: [Int32: SessionRecord] = [:]
        let claudeCountByCWD = Dictionary(grouping: processes.filter { $0.agent == .claude }.compactMap { $0.cwd.map(normalized) },
                                          by: { $0 }).mapValues(\.count)
        let ordered = processes.sorted { ($0.startedAt ?? .distantPast, $0.pid) > ($1.startedAt ?? .distantPast, $1.pid) }
        for process in ordered {
            guard let cwd = process.cwd.map(normalized) else { continue }
            if process.agent == .claude, claudeCountByCWD[cwd, default: 0] != 1 { continue }
            let candidate = records
                .filter { $0.agent == process.agent && !used.contains($0.path) && $0.cwd.map(normalized) == cwd }
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .first { record in
                    guard process.agent != .codex, let startedAt = process.startedAt else { return true }
                    return record.modifiedAt >= startedAt
                }
            if let candidate {
                result[process.pid] = candidate
                used.insert(candidate.path)
            }
        }
        return result
    }

    static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
