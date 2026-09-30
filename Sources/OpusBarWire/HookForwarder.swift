import Foundation

/// Everything `opusbar-hook` does, as a testable function.
/// Must never slow down or break the agent: always returns 0 and never writes to stdout.
public enum HookForwarder {
    public static let stdinCapBytes = 1 << 20
    public static let connectTimeoutMs: Int32 = 200

    public static func run(
        stdin: FileHandle,
        arguments: [String] = [],
        environment: [String: String],
        parentPID: Int32,
        nowMs: () -> Int64,
        paths: OpusBarPaths
    ) -> Int32 {
        let ts = nowMs()
        // Removed agents (pi, OMP) may still have an extension calling us: never report them as Claude.
        guard !AgentKind.namesUnknownAgent(arguments) else {
            _ = readCapped(stdin)
            return 0
        }
        guard let input = readCapped(stdin) else { return 0 }
        guard let slim = try? SlimEvent.slim(hookJSON: input) else { return 0 }
        let event = WireEvent(ts: ts, pid: parentPID, term: TermInfo.from(environment: environment),
                              agent: AgentKind.fromArguments(arguments), e: slim)
        guard let line = try? event.encodedLine() else { return 0 }
        _ = SocketClient.send(line, toSocketAt: paths.socket.path, timeoutMs: connectTimeoutMs)
        return 0
    }

    /// Reads stdin to EOF so the writer never blocks, keeping at most `stdinCapBytes`.
    /// Returns nil when the input was larger than the cap (a truncated payload is not valid JSON anyway).
    static func readCapped(_ handle: FileHandle) -> Data? {
        var kept = Data()
        var overflowed = false
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            if overflowed { continue }
            if kept.count + chunk.count > stdinCapBytes {
                overflowed = true
                kept = Data()
            } else {
                kept.append(chunk)
            }
        }
        return overflowed ? nil : kept
    }
}
