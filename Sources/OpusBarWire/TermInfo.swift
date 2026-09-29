/// Terminal identifiers, used to name where a session runs. Only these four variables are read.
public struct TermInfo: Codable, Equatable, Sendable {
    public var termProgram: String?
    public var termSessionId: String?
    public var itermSessionId: String?
    public var tmux: String?

    public init(termProgram: String? = nil, termSessionId: String? = nil, itermSessionId: String? = nil, tmux: String? = nil) {
        self.termProgram = termProgram
        self.termSessionId = termSessionId
        self.itermSessionId = itermSessionId
        self.tmux = tmux
    }

    /// nil when none of the four variables are set.
    public static func from(environment: [String: String]) -> TermInfo? {
        let info = TermInfo(
            termProgram: environment["TERM_PROGRAM"],
            termSessionId: environment["TERM_SESSION_ID"],
            itermSessionId: environment["ITERM_SESSION_ID"],
            tmux: environment["TMUX"]
        )
        return info == TermInfo() ? nil : info
    }
}
