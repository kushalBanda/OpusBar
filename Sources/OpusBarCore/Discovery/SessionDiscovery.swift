import Foundation
import OpusBarWire

/// A live agent process, with its on-disk session record when one could be matched.
public struct DiscoveredProcess: Equatable, Sendable {
    public var pid: Int32
    public var agent: AgentKind
    public var cwd: String?
    public var startedAt: Date?
    public var record: SessionRecord?
    public var host: SessionHost?

    public init(pid: Int32, agent: AgentKind, cwd: String?, startedAt: Date?, record: SessionRecord? = nil,
                host: SessionHost? = nil) {
        self.host = host
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
    let codexHomes: @Sendable () -> [URL]

    public init(lister: ProcessListing = DarwinProcessLister(),
                limit: Int = 64,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                claudeProjectRoots: (@Sendable () -> [URL])? = nil,
                codexHomes: (@Sendable () -> [URL])? = nil) {
        self.lister = lister
        self.limit = limit
        self.environment = environment
        home = ClaudeConfigPaths.homeDirectory(environment: environment)
        let home = home
        self.claudeProjectRoots = claudeProjectRoots ?? { SessionDiscovery.defaultClaudeProjectRoots(home: home, environment: environment) }
        self.codexHomes = codexHomes ?? { CodexHomes.all(environment: environment, userAdded: []).map(\.root) }
    }

    public func scan(now: Date = Date()) -> [DiscoveredProcess] {
        let all = lister.processes()
        let agentProcesses = AgentProcessClassifier.agentProcesses(from: all, limit: limit)
        let byPID = Dictionary(all.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var found = agentProcesses.map { process, agent in
            DiscoveredProcess(pid: process.pid, agent: agent,
                              cwd: process.cwd ?? lister.workingDirectory(pid: process.pid),
                              startedAt: process.startedAt,
                              host: SessionHost.resolve(pid: process.pid, processes: byPID))
        }
        guard !found.isEmpty else { return [] }
        var budget = ScanBudget()
        var records: [SessionRecord] = []
        let agents = Set(found.map(\.agent))
        var exact: [Int32: SessionRecord] = [:]
        if agents.contains(.claude) {
            var roots = claudeProjectRoots()
            if agentProcesses.contains(where: { $0.1 == .claude && AgentProcessClassifier.isClaudeDesktop($0.0) }) {
                roots += SessionRecordReader.claudeDesktopProjectRoots(home: home, budget: &budget)
            }
            exact = SessionRecordReader.claudeLiveSessions(
                processes: found.filter { $0.agent == .claude }.map { ($0.pid, $0.startedAt) },
                configRoots: roots.map { $0.deletingLastPathComponent() })
            for cwd in Set(found.filter { $0.agent == .claude }.compactMap(\.cwd)) {
                records += SessionRecordReader.claudeTranscripts(cwd: cwd, projectRoots: roots, now: now, budget: &budget)
            }
        }
        if agents.contains(.codex) {
            for codexHome in codexHomes() {
                records += SessionRecordReader.codexRollouts(codexHome: codexHome, now: now, budget: &budget)
            }
        }
        let matches = SessionCorrelator.match(found, records: records, exact: exact)
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
