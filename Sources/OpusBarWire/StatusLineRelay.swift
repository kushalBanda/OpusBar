import Foundation

/// Claude's plan limits as Claude Code hands them to its status line command (`rate_limits`), refreshed with
/// each reply. Only the windows are kept: the rest of the status line input (folder, model, cost, transcript)
/// never leaves the hook.
public struct LiveLimits: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public var usedPercent: Double
        /// Unix seconds.
        public var resetsAt: Double?

        public init(usedPercent: Double, resetsAt: Double?) {
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
        }
    }

    /// Unix seconds, when the status line ran.
    public var observedAt: Double
    /// By Claude's key: `five_hour`, `seven_day`.
    public var windows: [String: Window]

    public init(observedAt: Double, windows: [String: Window]) {
        self.observedAt = observedAt
        self.windows = windows
    }

    /// Nil when the input has no usable `rate_limits` (an API key, or no reply yet in this session).
    public static func parse(statusLine data: Data, now: Date) -> LiveLimits? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let limits = json["rate_limits"] as? [String: Any] else { return nil }
        var windows: [String: Window] = [:]
        for (key, value) in limits {
            guard let entry = value as? [String: Any],
                  let used = entry["used_percentage"] as? NSNumber, CFGetTypeID(used) != CFBooleanGetTypeID(),
                  used.doubleValue.isFinite else { continue }
            // A resumed session reports 0 % with no reset time until its first reply: a placeholder, not a
            // reading. A real window always has a reset time once anything is spent in it.
            guard let resets = seconds(entry["resets_at"]) else { continue }
            windows[key] = Window(usedPercent: used.doubleValue, resetsAt: resets)
        }
        return windows.isEmpty ? nil : LiveLimits(observedAt: now.timeIntervalSince1970, windows: windows)
    }

    /// Unix seconds or milliseconds, or an ISO 8601 string.
    static func seconds(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let raw = number.doubleValue
            guard raw.isFinite, raw > 0 else { return nil }
            return raw > 1e12 ? raw / 1_000 : raw
        }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)?.timeIntervalSince1970
    }

    public static func read(_ url: URL) -> LiveLimits? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(LiveLimits.self, from: $0) }
    }
}

/// `opusbar-hook statusline <root> [<command>]`, both base64: OpusBar's place in front of a Claude profile's
/// status line. Saves the live limits for that profile, then runs the profile's own status line command with
/// the same input and hands its output and exit status back to Claude Code.
public enum StatusLineRelay {
    public static let argument = "statusline"
    /// An unchanged reading is saved again only this often, so "updated" stays near now while Claude works.
    static let rewriteAfter: TimeInterval = 20

    public static func run(stdin: FileHandle, arguments: [String], paths: OpusBarPaths, now: Date) -> Int32 {
        let input = HookForwarder.readCapped(stdin) ?? Data()
        if let root = arguments.dropFirst().first.flatMap(decode), let limits = LiveLimits.parse(statusLine: input, now: now) {
            save(limits, to: paths.liveLimitsFile(profileRoot: root))
        }
        guard let command = arguments.dropFirst(2).first.flatMap(decode), !command.isEmpty else { return 0 }
        return runCommand(command, input: input)
    }

    static func save(_ limits: LiveLimits, to url: URL) {
        if let known = LiveLimits.read(url), known.windows == limits.windows,
           limits.observedAt - known.observedAt < rewriteAfter { return }
        guard let data = try? JSONEncoder().encode(limits) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: .atomic)
    }

    /// Through `/bin/sh -c`, as Claude Code runs it; stdout and stderr go straight to Claude Code.
    static func runCommand(_ command: String, input: Data) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardInput = pipe
        do { try process.run() } catch { return 1 }
        // The command may exit without reading its input: never die of SIGPIPE writing it.
        signal(SIGPIPE, SIG_IGN)
        try? pipe.fileHandleForWriting.write(contentsOf: input)
        try? pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }

    public static func encode(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

    public static func decode(_ text: String) -> String? {
        Data(base64Encoded: text).flatMap { String(data: $0, encoding: .utf8) }
    }
}
