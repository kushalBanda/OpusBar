import Foundation
import OpusBarWire

/// Metadata of one on-disk agent session. Only id, cwd and timestamps; message bodies are never kept.
public struct SessionRecord: Equatable, Sendable {
    public var id: String
    public var agent: AgentKind
    public var cwd: String?
    public var modifiedAt: Date
    public var path: String

    public init(id: String, agent: AgentKind, cwd: String?, modifiedAt: Date, path: String) {
        self.id = id
        self.agent = agent
        self.cwd = cwd
        self.modifiedAt = modifiedAt
        self.path = path
    }
}

/// Caps directory work per discovery pass: entries visited and wall time.
public struct ScanBudget {
    private var remainingEntries: Int
    private let deadline: Date
    private let clock: () -> Date

    public init(maxEntries: Int = 512, timeLimit: TimeInterval = 0.25, clock: @escaping () -> Date = Date.init) {
        remainingEntries = maxEntries
        deadline = clock().addingTimeInterval(timeLimit)
        self.clock = clock
    }

    public var hasTimeRemaining: Bool { remainingEntries > 0 && clock() < deadline }

    /// Direct children of `directory` (no recursion, hidden files skipped) with modification dates.
    mutating func children(of directory: URL) -> [(url: URL, modifiedAt: Date, isDirectory: Bool)] {
        guard hasTimeRemaining,
              let enumerator = FileManager.default.enumerator(
                  at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                  options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        else { return [] }
        var entries: [(URL, Date, Bool)] = []
        while hasTimeRemaining, let url = enumerator.nextObject() as? URL {
            remainingEntries -= 1
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard let modifiedAt = values?.contentModificationDate else { continue }
            entries.append((url, modifiedAt, values?.isDirectory == true))
        }
        return entries
    }
}

public enum SessionRecordReader {
    static let maxHeaderBytes = 256 * 1024

    // MARK: Claude Code

    /// Claude names a project folder after the cwd with every character other than ASCII letters and digits as "-".
    public static func claudeProjectFolderName(for cwd: String) -> String {
        String(cwd.unicodeScalars.map { scalar in
            let v = scalar.value
            let isAlphanumeric = (48...57).contains(v) || (65...90).contains(v) || (97...122).contains(v)
            return isAlphanumeric ? Character(scalar) : "-"
        })
    }

    /// Transcripts for one cwd across all known project roots, newest first. The file name is the session id.
    public static func claudeTranscripts(cwd: String, projectRoots: [URL], now: Date,
                                         budget: inout ScanBudget) -> [SessionRecord] {
        let folder = claudeProjectFolderName(for: cwd)
        return projectRoots
            .flatMap { budget.children(of: $0.appending(path: folder, directoryHint: .isDirectory)) }
            .filter { !$0.isDirectory && $0.url.pathExtension == "jsonl" }
            .map { SessionRecord(id: $0.url.deletingPathExtension().lastPathComponent, agent: .claude, cwd: cwd,
                                 modifiedAt: min($0.modifiedAt, now), path: $0.url.path) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: Codex

    /// Rollouts from today and yesterday (`sessions/YYYY/MM/DD/rollout-*.jsonl`), newest first, first line parsed.
    public static func codexRollouts(codexHome: URL, now: Date, limit: Int = 128,
                                     budget: inout ScanBudget) -> [SessionRecord] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy/MM/dd"
        let days = [now, now.addingTimeInterval(-86_400)]
        let candidates = days
            .flatMap { budget.children(of: codexHome.appending(path: "sessions/\(formatter.string(from: $0))")) }
            .filter { !$0.isDirectory && $0.url.lastPathComponent.hasPrefix("rollout-") && $0.url.pathExtension == "jsonl" }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
        var records: [SessionRecord] = []
        for candidate in candidates where budget.hasTimeRemaining {
            guard let line = firstLines(of: candidate.url, count: 1).first,
                  let meta = codexSessionMeta(line)
            else { continue }
            records.append(SessionRecord(id: meta.id, agent: .codex, cwd: meta.cwd,
                                         modifiedAt: min(candidate.modifiedAt, now), path: candidate.url.path))
        }
        return records
    }

    /// `{"type":"session_meta","payload":{"id"|"session_id", "cwd", …}}`
    static func codexSessionMeta(_ line: Data) -> (id: String, cwd: String?)? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let id = (payload["session_id"] as? String) ?? (payload["id"] as? String)
        else { return nil }
        return (id, payload["cwd"] as? String)
    }

    // MARK: pi / OMP

    /// Session files under `roots/<bucket>/*.jsonl` changed at or after `since` (the oldest live process start).
    /// Bucket names are escaped or hashed cwds, so the header's cwd is used instead of decoding them.
    public static func piFamilyRecords(roots: [URL], dialect: AgentKind, since: Date, now: Date,
                                       budget: inout ScanBudget) -> [SessionRecord] {
        var records: [SessionRecord] = []
        for root in roots {
            for bucket in budget.children(of: root) where bucket.isDirectory && bucket.modifiedAt >= since {
                for file in budget.children(of: bucket.url)
                where !file.isDirectory && file.url.pathExtension == "jsonl" && file.modifiedAt >= since {
                    guard budget.hasTimeRemaining,
                          let header = piFamilyHeader(firstLines(of: file.url, count: 2), dialect: dialect)
                    else { continue }
                    records.append(SessionRecord(id: header.id, agent: dialect, cwd: header.cwd,
                                                 modifiedAt: min(file.modifiedAt, now), path: file.url.path))
                }
            }
        }
        return records.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// pi: first line `{"type":"session","version":3,"id",…,"cwd"}`. OMP may put a `{"type":"title"}` line first.
    static func piFamilyHeader(_ lines: [Data], dialect: AgentKind) -> (id: String, cwd: String?)? {
        var objects = lines.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if dialect == .omp, objects.first?["type"] as? String == "title" { objects.removeFirst() }
        guard let header = objects.first, header["type"] as? String == "session",
              let id = header["id"] as? String
        else { return nil }
        if dialect == .pi, header["version"] as? Int != 3 { return nil }
        return (id, header["cwd"] as? String)
    }

    /// Default pi and OMP session roots that exist.
    public static func piFamilyRoots(dialect: AgentKind, home: URL, environment: [String: String]) -> [URL] {
        var roots: [URL]
        switch dialect {
        case .pi:
            roots = [home.appending(path: ".pi/agent/sessions", directoryHint: .isDirectory)]
        case .omp:
            roots = [home.appending(path: ".omp/agent/sessions", directoryHint: .isDirectory)]
            let xdg = environment["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
                ?? home.appending(path: ".local/share", directoryHint: .isDirectory)
            roots.append(xdg.appending(path: "omp/sessions", directoryHint: .isDirectory))
        default:
            roots = []
        }
        return roots.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Helpers

    /// Up to `count` complete lines from the start of a file, reading at most `maxHeaderBytes`.
    static func firstLines(of url: URL, count: Int) -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        var buffer = Data()
        var lines: [Data] = []
        while lines.count < count, buffer.count < maxHeaderBytes {
            guard let chunk = try? handle.read(upToCount: 16 * 1024), !chunk.isEmpty else { break }
            buffer.append(chunk)
            while lines.count < count, let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(buffer.prefix(upTo: newline))
                buffer = Data(buffer.suffix(from: buffer.index(after: newline)))
            }
        }
        return lines
    }
}
