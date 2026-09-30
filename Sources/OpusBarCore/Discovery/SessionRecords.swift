import Foundation
import OpusBarWire

/// Metadata of one on-disk agent session. Only id, cwd and timestamps; message bodies are never kept.
public struct SessionRecord: Equatable, Sendable {
    /// What the agent itself reports about a running session, when it does (Claude's per-pid file).
    public enum LiveStatus: String, Sendable {
        case busy, idle
    }

    public var id: String
    public var agent: AgentKind
    public var cwd: String?
    public var modifiedAt: Date
    public var path: String
    /// The session's own name (e.g. Claude's `quant-8d`), to tell apart sessions in one folder.
    public var title: String?
    public var status: LiveStatus?
    /// When the agent last changed `status`.
    public var statusAt: Date?

    public init(id: String, agent: AgentKind, cwd: String?, modifiedAt: Date, path: String,
                title: String? = nil, status: LiveStatus? = nil, statusAt: Date? = nil) {
        self.id = id
        self.agent = agent
        self.cwd = cwd
        self.modifiedAt = modifiedAt
        self.path = path
        self.title = title
        self.status = status
        self.statusAt = statusAt
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
    /// Claude writes `<config root>/sessions/<pid>.json` for each running session: its id, cwd, name,
    /// status and the process start time. Read only for the pids asked about, never listed.
    /// A file counts only if its recorded start matches the live process (within 2 s), so a reused
    /// pid never inherits a dead session's file.
    public static func claudeLiveSessions(processes: [(pid: Int32, startedAt: Date?)], configRoots: [URL]) -> [Int32: SessionRecord] {
        var result: [Int32: SessionRecord] = [:]
        for process in processes {
            for root in configRoots {
                let file = root.appending(path: "sessions/\(process.pid).json")
                guard let record = claudeLiveSession(at: file, pid: process.pid, startedAt: process.startedAt, configRoot: root)
                else { continue }
                result[process.pid] = record
                break
            }
        }
        return result
    }

    static func claudeLiveSession(at file: URL, pid: Int32, startedAt: Date?, configRoot: URL) -> SessionRecord? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["pid"] as? NSNumber)?.int32Value == pid,
              let id = json["sessionId"] as? String, !id.isEmpty
        else { return nil }
        if let startedAt {
            guard let recorded = (json["procStart"] as? String).flatMap(parseProcStart),
                  abs(recorded.timeIntervalSince(startedAt)) <= 2
            else { return nil }
        }
        let cwd = json["cwd"] as? String
        let transcript = cwd.map {
            configRoot.appending(path: "projects/\(claudeProjectFolderName(for: $0))/\(id).jsonl")
        }
        let transcriptModified = transcript.flatMap {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }
        let updated = (json["updatedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return SessionRecord(id: id, agent: .claude, cwd: cwd,
                             modifiedAt: [transcriptModified, updated].compactMap { $0 }.max() ?? .distantPast,
                             path: transcript?.path ?? file.path,
                             title: (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             status: (json["status"] as? String).flatMap(SessionRecord.LiveStatus.init(rawValue:)),
                             statusAt: (json["statusUpdatedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) })
    }

    /// `procStart` is the process start in C `ctime` form, UTC: "Sun Sep 27 16:38:37 2026".
    static func parseProcStart(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.date(from: text.split(separator: " ").joined(separator: " "))
    }

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

    /// Claude desktop keeps per-session config roots under Application Support; each may hold a
    /// `.claude/projects`. Walks at most 4 levels, never follows symlinks, skips build folders.
    public static func claudeDesktopProjectRoots(home: URL, budget: inout ScanBudget) -> [URL] {
        let support = home.appending(path: "Library/Application Support/Claude", directoryHint: .isDirectory)
        let skipped: Set<String> = [".build", ".git", "build", "DerivedData", "node_modules", "outputs", "target"]
        var queue = ["claude-code-sessions", "local-agent-mode-sessions"].map {
            (url: support.appending(path: $0, directoryHint: .isDirectory), depth: 0)
        }
        var roots: [URL] = []
        var index = 0
        while index < queue.count, budget.hasTimeRemaining {
            let (url, depth) = queue[index]
            index += 1
            let projects = url.appending(path: ".claude/projects", directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: projects.path, isDirectory: &isDirectory), isDirectory.boolValue {
                roots.append(projects)
            }
            guard depth < 4 else { continue }
            for child in budget.children(of: url)
            // `children(of:)` skips hidden entries, and a symlink never reports isDirectory.
            where child.isDirectory && !skipped.contains(child.url.lastPathComponent) {
                queue.append((child.url, depth + 1))
            }
        }
        return roots
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
