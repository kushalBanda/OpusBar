import Foundation
import OpusBarWire

/// Everything read so far from the agents' logs, kept for `history`. Files are read where they are,
/// from where each one stopped; nothing is copied or saved. Blocking and not thread-safe: the owner
/// confines it to one serial queue.
public final class UsageStore {
    public static let defaultHistory: TimeInterval = 90 * 86_400

    private let claudeRoots: () -> [URL]
    private let codexRoots: () -> [URL]
    private let history: TimeInterval
    private let maxLineBytes: Int
    private var ledger: UsageLedger
    private var cursors: [String: UsageLogCursor] = [:]
    private let projects = UsageProjects()
    /// Canonical root paths from the last refresh, with the agent whose logs they hold and the account
    /// folder above them (`projects/`, `sessions/` sit in the profile or home).
    private var roots: [Root] = []
    private struct Root { var path: String; var agent: AgentKind; var account: String }
    /// The account folder of each file read.
    private var accounts: [String: String] = [:]
    public var watchedRoots: [String] { roots.map(\.path) }

    public init(claudeRoots: @escaping () -> [URL], codexRoots: @escaping () -> [URL] = { [] }, prices: UsagePriceList,
                history: TimeInterval = defaultHistory, maxLineBytes: Int = 32 << 20) {
        self.claudeRoots = claudeRoots
        self.codexRoots = codexRoots
        self.history = history
        self.maxLineBytes = maxLineBytes
        ledger = UsageLedger(prices: prices)
    }

    public var records: [UsageRecord] { ledger.records }

    /// Bytes consumed across all files (for tests and the first-scan budget).
    public var bytesRead: Int { cursors.values.reduce(0) { $0 + Int($1.offset) } }

    public func totals(since: Date) -> UsageTotals { ledger.totals(since: since) }

    /// Each Codex home's newest limit reading across its rollouts read so far, by home.
    public var codexLimits: [UsageLimits] {
        var newest: [String: UsageLimits] = [:]
        for cursor in cursors.values where cursor.agent == .codex {
            guard var limits = cursor.codex.limits else { continue }
            let home = accounts[cursor.path] ?? ""
            if let known = newest[home], known.observedAt >= limits.observedAt { continue }
            limits.account = home
            limits.label = AccountFolder.name(home)
            newest[home] = limits
        }
        return newest.values.sorted { $0.account < $1.account }
    }

    /// Finds log files changed within the history window and reads what each gained. Covers files the
    /// watcher missed (new roots, events dropped) and drops records past the window. `recent` limits the
    /// pass to files changed that recently: every reply of the last 24 hours is in a file changed within
    /// them, so a short first pass makes the 24 h figures ready long before the 90-day read ends.
    public func refresh(now: Date = Date(), recent: TimeInterval? = nil) {
        let horizon = now.addingTimeInterval(-history)
        let changedSince = recent.map { max(horizon, now.addingTimeInterval(-$0)) } ?? horizon
        resolveRoots()
        var files: [(path: String, root: Root)] = []
        for root in roots {
            for path in UsageLogReader.logs(under: [URL(fileURLWithPath: root.path)], changedSince: changedSince) {
                files.append((UsageLogReader.canonical(path), root))
            }
        }
        read(files)
        ledger.drop(before: horizon)
    }

    /// `sessions/` and `archived_sessions/` of every known Codex home, that exist.
    public static func codexRoots(homes: [CodexHome]) -> [URL] {
        homes.flatMap(\.sessionRoots).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The same for `~/.codex`, `$CODEX_HOME` and detected `~/.codex-*` homes.
    public static func codexRoots(environment: [String: String]) -> [URL] {
        codexRoots(homes: CodexHomes.all(environment: environment, userAdded: []))
    }

    private func resolveRoots() {
        var seen = Set<String>()
        roots = (claudeRoots().map { ($0, AgentKind.claude) } + codexRoots().map { ($0, AgentKind.codex) })
            .filter { FileManager.default.fileExists(atPath: $0.0.path) }
            .map { url, agent in
                let path = UsageLogReader.canonical(url.path)
                return Root(path: path, agent: agent, account: URL(fileURLWithPath: path).deletingLastPathComponent().path)
            }
            .filter { seen.insert($0.path).inserted }
    }

    /// Reads the given files (watcher events). Paths outside the roots and non-log files are ignored.
    public func read(paths: [String], now: Date = Date()) {
        if roots.isEmpty { resolveRoots() }
        for path in paths where path.hasSuffix(".jsonl") {
            let path = UsageLogReader.canonical(path)
            guard let root = roots.first(where: { path.hasPrefix($0.path + "/") }) else { continue }
            read([(path, root)])
        }
        ledger.drop(before: now.addingTimeInterval(-history))
    }

    /// Parsing is most of a first scan (hundreds of megabytes of JSON), so files are read in parallel: each
    /// worker owns whole files (a cursor is never shared) and only collects replies. The replies then join
    /// the ledger one at a time in file order, so the result is the same as reading one file after another.
    private func read(_ files: [(path: String, root: Root)]) {
        let batch = files.map { file -> UsageLogCursor in
            let cursor = cursors[file.path] ?? UsageLogCursor(path: file.path, agent: file.root.agent)
            cursors[file.path] = cursor
            accounts[file.path] = file.root.account
            return cursor
        }
        let replies = ParallelReplies(count: batch.count)
        let maxLineBytes = maxLineBytes
        DispatchQueue.concurrentPerform(iterations: batch.count) { index in
            replies.set(index, Self.collect(batch[index], maxLineBytes: maxLineBytes))
        }
        for (index, fileReplies) in replies.all.enumerated() {
            for var reply in fileReplies {
                reply.record.project = projects.name(for: reply.record.project)
                reply.record.account = files[index].root.account
                ledger.add(reply.record, key: reply.key)
            }
        }
    }

    private static func collect(_ cursor: UsageLogCursor, maxLineBytes: Int) -> [(key: String, record: UsageRecord)] {
        var replies: [(key: String, record: UsageRecord)] = []
        UsageLogReader.readAppended(cursor, maxLineBytes: maxLineBytes) { line in
            let parsed = switch cursor.agent {
            case .claude: ClaudeUsageParser.parse(line)
            case .codex: CodexUsageParser.parse(line, state: &cursor.codex)
            }
            if let parsed { replies.append(parsed) }
        }
        return replies
    }
}

/// One slot per file, each written by exactly one worker.
private final class ParallelReplies: @unchecked Sendable {
    private var slots: [[(key: String, record: UsageRecord)]]
    private let lock = NSLock()

    init(count: Int) { slots = Array(repeating: [], count: count) }

    func set(_ index: Int, _ replies: [(key: String, record: UsageRecord)]) { lock.withLock { slots[index] = replies } }

    var all: [[(key: String, record: UsageRecord)]] { lock.withLock { slots } }
}

/// Project names for usage: the git repository a folder belongs to, so replies made in a repo's subfolders
/// count toward the repo. Falls back to the folder's own name (no repo, or the folder is gone). Cached per
/// folder: a first scan meets the same few folders tens of thousands of times.
final class UsageProjects {
    private var cache: [String: String] = [:]
    private let isRepository: (URL) -> Bool

    init(isRepository: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.appending(path: ".git").path) }) {
        self.isRepository = isRepository
    }

    func name(for folder: String) -> String {
        guard !folder.isEmpty else { return "" }
        if let known = cache[folder] { return known }
        var current = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
        var name = current.lastPathComponent
        while current.pathComponents.count > 1 {
            if isRepository(current) {
                name = current.lastPathComponent
                break
            }
            current = current.deletingLastPathComponent()
        }
        cache[folder] = name
        return name
    }
}
