import Foundation
import OpusBarWire

/// A live agent process, with its on-disk session record when one could be matched.
public struct DiscoveredProcess: Equatable, Sendable {
    public var pid: Int32
    public var agent: AgentKind
    public var cwd: String?
    public var startedAt: Date?
    public var record: SessionRecord?

    public init(pid: Int32, agent: AgentKind, cwd: String?, startedAt: Date?, record: SessionRecord? = nil) {
        self.pid = pid
        self.agent = agent
        self.cwd = cwd
        self.startedAt = startedAt
        self.record = record
    }

    /// The agent's own session id when known (the same id its hooks send), else `pid:<n>`.
    public var sessionId: String { record?.id ?? Self.sessionId(pid: pid) }
    public static func sessionId(pid: Int32) -> String { "pid:\(pid)" }
}

/// One bounded pass: processes, then only the session folders those processes point at. Blocking; call off the main thread.
public struct SessionDiscovery: Sendable {
    let lister: ProcessListing
    let limit: Int
    let home: URL
    let environment: [String: String]
    let claudeProjectRoots: @Sendable () -> [URL]

    public init(lister: ProcessListing = DarwinProcessLister(),
                limit: Int = 64,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                claudeProjectRoots: (@Sendable () -> [URL])? = nil) {
        self.lister = lister
        self.limit = limit
        self.environment = environment
        home = ClaudeConfigPaths.homeDirectory(environment: environment)
        let home = home
        self.claudeProjectRoots = claudeProjectRoots ?? { SessionDiscovery.defaultClaudeProjectRoots(home: home, environment: environment) }
    }

    public func scan(now: Date = Date()) -> [DiscoveredProcess] {
        var found = AgentProcessClassifier.agentProcesses(from: lister.processes(), limit: limit).map { process, agent in
            DiscoveredProcess(pid: process.pid, agent: agent,
                              cwd: process.cwd ?? lister.workingDirectory(pid: process.pid),
                              startedAt: process.startedAt)
        }
        guard !found.isEmpty else { return [] }
        var budget = ScanBudget()
        var records: [SessionRecord] = []
        let agents = Set(found.map(\.agent))
        if agents.contains(.claude) {
            let roots = claudeProjectRoots()
            for cwd in Set(found.filter { $0.agent == .claude }.compactMap(\.cwd)) {
                records += SessionRecordReader.claudeTranscripts(cwd: cwd, projectRoots: roots, now: now, budget: &budget)
            }
        }
        if agents.contains(.codex) {
            let codexHome = environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
                ?? home.appending(path: ".codex", directoryHint: .isDirectory)
            records += SessionRecordReader.codexRollouts(codexHome: codexHome, now: now, budget: &budget)
        }
        for dialect in [AgentKind.pi, .omp] where agents.contains(dialect) {
            let since = found.filter { $0.agent == dialect }.compactMap(\.startedAt).min() ?? now.addingTimeInterval(-86_400)
            let roots = SessionRecordReader.piFamilyRoots(dialect: dialect, home: home, environment: environment)
            records += SessionRecordReader.piFamilyRecords(roots: roots, dialect: dialect, since: since, now: now, budget: &budget)
        }
        let matches = SessionCorrelator.match(found, records: records)
        for index in found.indices { found[index].record = matches[found[index].pid] }
        return found
    }

    /// `projects/` under the resolved config root, plus `~/.claude` and `~/.config/claude`, that exist.
    public static func defaultClaudeProjectRoots(home: URL, environment: [String: String]) -> [URL] {
        let candidates = [
            ClaudeConfigPaths.projectsRoot(environment: environment),
            home.appending(path: ".claude/projects", directoryHint: .isDirectory),
            home.appending(path: ".config/claude/projects", directoryHint: .isDirectory),
        ]
        var seen = Set<String>()
        return candidates.filter {
            seen.insert($0.standardizedFileURL.path).inserted && FileManager.default.fileExists(atPath: $0.path)
        }
    }
}
