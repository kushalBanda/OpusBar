import Foundation
import OpusBarWire

/// Adds and removes OpusBar's hooks in one hooks JSON file (Claude `settings.json`, later Codex `hooks.json`).
/// Never overwrites: reads, merges, backs up, writes atomically, re-reads to verify.
public struct HookInstaller: Sendable {
    public enum Status: Equatable, Sendable {
        case installed
        case notInstalled
        case partial(missing: [HookEventName])
        /// The file exists but isn't a JSON object. Nothing is ever written in this state.
        case unreadable(String)
    }

    public enum InstallError: Error, Equatable {
        case unreadable(String)
        case hookBinaryMissing(String)
        case verifyFailed
    }

    public static let backupsKept = 10

    public let settingsURL: URL
    public let events: [HookEventName]
    /// The stable hook copy the entries point at.
    public let hookBinary: URL
    /// Extra arguments after the binary, e.g. `--agent codex`.
    public let hookArguments: [String]
    public let backupsDir: URL
    /// Claude: async, never blocks. Codex: sync, because `codex exec` exits before pending async hooks run (Stop was lost).
    public let async: Bool
    let now: @Sendable () -> Date

    public init(settingsURL: URL, events: [HookEventName] = HookEventName.subscribed, hookBinary: URL,
                hookArguments: [String] = [], backupsDir: URL, async: Bool = true,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.settingsURL = settingsURL
        self.events = events
        self.hookBinary = hookBinary
        self.hookArguments = hookArguments
        self.backupsDir = backupsDir
        self.async = async
        self.now = now
    }

    /// The command string Claude runs: quoted absolute path (it contains a space), then arguments.
    public var hookCommand: String {
        (["\"\(hookBinary.path)\""] + hookArguments).joined(separator: " ")
    }

    // MARK: Status

    public func status() -> Status {
        switch readSettings() {
        case .missing: return .notInstalled
        case .invalid(let reason): return .unreadable(reason)
        case .object(let settings): return Self.status(of: settings, events: events)
        }
    }

    static func status(of settings: [String: Any], events: [HookEventName]) -> Status {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let missing = events.filter { event in
            let groups = hooks[event.rawValue] as? [[String: Any]] ?? []
            return !groups.contains { group in (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs) }
        }
        if missing.isEmpty { return .installed }
        return missing.count == events.count ? .notInstalled : .partial(missing: missing)
    }

    // MARK: Install / uninstall

    /// Copies the hook binary into place, backs the file up, merges our entries, writes, verifies.
    @discardableResult
    public func install(hookSource: URL) throws -> Status {
        let settings: [String: Any]
        switch readSettings() {
        case .missing: settings = [:]
        case .invalid(let reason): throw InstallError.unreadable(reason)
        case .object(let object): settings = object
        }
        try installBinary(from: hookSource)
        try backUp()
        try write(Self.merged(settings, command: hookCommand, events: events, async: async))
        guard status() == .installed else { throw InstallError.verifyFailed }
        return .installed
    }

    /// Removes only entries whose command runs an `opusbar-hook` binary. Leaves the stable binary in place,
    /// since other profiles may still use it.
    @discardableResult
    public func uninstall() throws -> Status {
        guard case .object(let settings) = readSettings() else { return status() }
        try backUp()
        try write(Self.unmerged(settings))
        return status()
    }

    // MARK: Pure merge

    /// Adds one `{matcher: "*", hooks: [our command]}` group per event that has none of ours. Keeps every other key and hook.
    static func merged(_ settings: [String: Any], command: String, events: [HookEventName], async: Bool = true) -> [String: Any] {
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event.rawValue] as? [[String: Any]] ?? []
            let present = groups.contains { ($0["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs) }
            guard !present else { continue }
            var entry: [String: Any] = ["type": "command", "command": command, "timeout": 5]
            if async { entry["async"] = true }
            groups.append(["matcher": "*", "hooks": [entry]])
            hooks[event.rawValue] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    /// Drops our hook entries, then any group, event or `hooks` key left empty by that.
    static func unmerged(_ settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = entries.filter { !isOurs($0) }
                if remaining.count == entries.count { return group }
                if remaining.isEmpty { return nil }
                var group = group
                group["hooks"] = remaining
                return group
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    /// Ours = a command whose executable (first token, quotes stripped) is named `opusbar-hook`.
    /// Also catches dev entries pointing at `.build/debug/opusbar-hook`.
    static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let command = entry["command"] as? String else { return false }
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let executable: String
        if trimmed.hasPrefix("\""), let close = trimmed.dropFirst().firstIndex(of: "\"") {
            executable = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        } else {
            executable = String(trimmed.split(separator: " ", maxSplits: 1).first ?? "")
        }
        return URL(fileURLWithPath: executable).lastPathComponent == "opusbar-hook"
    }

    // MARK: Files

    enum Read { case missing, invalid(String), object([String: Any]) }

    func readSettings() -> Read {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: settingsURL) else { return .invalid("Can't read the file") }
        if data.allSatisfy({ [0x20, 0x0A, 0x0D, 0x09].contains($0) }) { return .object([:]) }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return .invalid("Not valid JSON") }
        guard let dictionary = object as? [String: Any] else { return .invalid("Not a JSON object") }
        return .object(dictionary)
    }

    func write(_ settings: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
    }

    /// Copies the current file to `backupsDir/<name>.<timestamp>.json`, keeping the newest `backupsKept`.
    func backUp() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: backupsDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: now()).replacingOccurrences(of: ":", with: "-")
        let stem = settingsURL.deletingPathExtension().lastPathComponent
        var target = backupsDir.appending(path: "\(stem).\(stamp).json")
        var attempt = 2
        while fm.fileExists(atPath: target.path) {  // two changes within one millisecond
            target = backupsDir.appending(path: "\(stem).\(stamp)-\(attempt).json")
            attempt += 1
        }
        try fm.copyItem(at: settingsURL, to: target)
        let backups = (try? fm.contentsOfDirectory(atPath: backupsDir.path))?
            .filter { $0.hasPrefix(stem + ".") && $0.hasSuffix(".json") }
            .sorted() ?? []
        for old in backups.dropLast(Self.backupsKept) {
            try? fm.removeItem(at: backupsDir.appending(path: old))
        }
    }

    /// Copies the hook into the stable location (only when missing or changed), executable, without the
    /// download quarantine mark. Builds aren't notarized: a quarantined copy is killed by Gatekeeper when an
    /// agent runs it (exit 137), and approving OpusBar with Open Anyway doesn't clear the copy's mark.
    func installBinary(from source: URL) throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: source.path) else { throw InstallError.hookBinaryMissing(source.path) }
        if source.standardizedFileURL == hookBinary.standardizedFileURL { return }
        if fm.contentsEqual(atPath: source.path, andPath: hookBinary.path) {
            Self.clearQuarantine(hookBinary)
            return
        }
        try fm.createDirectory(at: hookBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = hookBinary.deletingLastPathComponent().appending(path: ".opusbar-hook.\(UUID().uuidString)")
        try fm.copyItem(at: source, to: staged)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
        Self.clearQuarantine(staged)
        _ = try fm.replaceItemAt(hookBinary, withItemAt: staged)
    }

    /// After an app update: the agents keep running the old copy until it is replaced. Only when OpusBar
    /// is connected somewhere (the copy exists); never creates it.
    public static func refreshBinary(_ hookBinary: URL, from source: URL) throws {
        guard FileManager.default.fileExists(atPath: hookBinary.path) else { return }
        try HookInstaller(settingsURL: hookBinary, hookBinary: hookBinary, backupsDir: hookBinary).installBinary(from: source)
    }

    static func clearQuarantine(_ url: URL) {
        removexattr(url.path, "com.apple.quarantine", 0)
    }
}
