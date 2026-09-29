import Foundation
import OpusBarWire

public struct Session: Identifiable, Equatable, Sendable {
    public let id: String
    public var agent: AgentKind
    public var cwd: String
    public var projectName: String
    public var branch: String?
    public var state: SessionState
    /// Short context for the row: "Edit", "Allow Bash?", "API error".
    public var detail: String?
    public var subagents: Int
    public var startedAt: Date
    /// When `state` last changed. The row's elapsed time counts from here.
    public var stateSince: Date
    public var lastEventAt: Date
    public var lastEventTs: Int64
    public var pid: Int32?
    public var term: TermInfo?
    /// Found by process discovery, no hook event yet. Its id is `pid:<n>` until a hook names it.
    public var isDiscovered: Bool

    public init(
        id: String,
        agent: AgentKind = .claude,
        cwd: String,
        branch: String? = nil,
        state: SessionState = .idle,
        detail: String? = nil,
        subagents: Int = 0,
        startedAt: Date,
        stateSince: Date? = nil,
        lastEventAt: Date? = nil,
        lastEventTs: Int64 = .min,
        pid: Int32? = nil,
        term: TermInfo? = nil,
        isDiscovered: Bool = false
    ) {
        self.id = id
        self.agent = agent
        self.cwd = cwd
        self.projectName = Self.projectName(for: cwd)
        self.branch = branch
        self.state = state
        self.detail = detail
        self.subagents = subagents
        self.startedAt = startedAt
        self.stateSince = stateSince ?? startedAt
        self.lastEventAt = lastEventAt ?? startedAt
        self.lastEventTs = lastEventTs
        self.pid = pid
        self.term = term
        self.isDiscovered = isDiscovered
    }

    static func projectName(for cwd: String) -> String {
        let name = URL(filePath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? "Unknown project" : name
    }

    /// Changes state and detail; `stateSince` moves only when the state really changes.
    mutating func transition(to newState: SessionState, detail newDetail: String?, now: Date) {
        if newState != state {
            state = newState
            stateSince = now
        }
        detail = newDetail
    }
}
