/// Terminal identifiers, used to name where a session runs and to bring it forward. Only these five variables are read.
public struct TermInfo: Codable, Equatable, Sendable {
    public var termProgram: String?
    public var termSessionId: String?
    public var itermSessionId: String?
    public var tmux: String?
    /// Orca's id for the terminal tab (`term_<uuid>`), which `orca terminal switch` takes.
    public var orcaTerminalHandle: String?

    public init(termProgram: String? = nil, termSessionId: String? = nil, itermSessionId: String? = nil, tmux: String? = nil,
                orcaTerminalHandle: String? = nil) {
        self.termProgram = termProgram
        self.termSessionId = termSessionId
        self.itermSessionId = itermSessionId
        self.tmux = tmux
        self.orcaTerminalHandle = orcaTerminalHandle
    }

    /// nil when none of the five variables are set.
    public static func from(environment: [String: String]) -> TermInfo? {
        let info = TermInfo(
            termProgram: environment["TERM_PROGRAM"],
            termSessionId: environment["TERM_SESSION_ID"],
            itermSessionId: environment["ITERM_SESSION_ID"],
            tmux: environment["TMUX"],
            orcaTerminalHandle: environment["ORCA_TERMINAL_HANDLE"]
        )
        return info == TermInfo() ? nil : info
    }
}
