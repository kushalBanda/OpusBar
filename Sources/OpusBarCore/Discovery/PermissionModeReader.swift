import Foundation

/// Where a Claude session's mode comes from before (or without) a hook reporting it. Claude sends
/// `permission_mode` only with prompt and tool events, not with SessionStart, so a fresh session and a
/// session started before OpusBar connected have none. In order of trust:
/// 1. the newest mode of this run in the transcript (Claude records it on each user message and in short
///    `permission-mode` lines at session start and around turns),
/// 2. the launch flags (`--permission-mode plan`, `--dangerously-skip-permissions`),
/// 3. `permissions.defaultMode` from the project's then the user's settings.
public enum PermissionModeReader {
    static let tailBytes = 128 * 1024
    /// Kernel start times are whole seconds; transcript timestamps have milliseconds.
    static let startSlack: TimeInterval = 2

    public static func claudeMode(arguments: [String], transcript: URL?, startedAt: Date?, cwd: String?,
                                  configRoot: URL) -> PermissionMode? {
        transcript.flatMap { lastPromptMode(transcript: $0, since: startedAt) }
            ?? launchMode(arguments: arguments)
            ?? defaultMode(cwd: cwd, configRoot: configRoot)
    }

    /// `--permission-mode <mode>` or `--permission-mode=<mode>`; the skip flag means Bypass.
    static func launchMode(arguments: [String]) -> PermissionMode? {
        for (index, argument) in arguments.enumerated() {
            if argument == "--dangerously-skip-permissions" { return .bypassPermissions }
            if argument.hasPrefix("--permission-mode=") {
                return PermissionMode(raw: String(argument.dropFirst("--permission-mode=".count)))
            }
            if argument == "--permission-mode", index + 1 < arguments.count {
                return PermissionMode(raw: arguments[index + 1])
            }
        }
        return nil
    }

    /// Local project settings beat shared project settings, which beat the user's.
    static func defaultMode(cwd: String?, configRoot: URL) -> PermissionMode? {
        var files: [URL] = []
        if let cwd, !cwd.isEmpty {
            let project = URL(filePath: cwd, directoryHint: .isDirectory).appending(path: ".claude")
            files += [project.appending(path: "settings.local.json"), project.appending(path: "settings.json")]
        }
        files.append(configRoot.appending(path: "settings.json"))
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let permissions = json["permissions"] as? [String: Any],
                  let mode = PermissionMode(raw: permissions["defaultMode"] as? String)
            else { continue }
            return mode
        }
        return nil
    }

    /// The newest mode in the transcript written since `since`. Older lines belong to an earlier run of a
    /// resumed session, whose mode may not carry over. User messages carry a timestamp; `permission-mode`
    /// lines don't, so they count only when the file changed since `since`. Reads only the file's tail.
    static func lastPromptMode(transcript: URL, since: Date?) -> PermissionMode? {
        if let since {
            guard let modified = (try? FileManager.default.attributesOfItem(atPath: transcript.path))?[.modificationDate] as? Date,
                  modified >= since.addingTimeInterval(-startSlack) else { return nil }
        }
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let tail = try? handle.readToEnd() else { return nil }
        let marker = Data("\"permissionMode\"".utf8)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Newest first; the first line of a mid-file tail may be cut, and then simply fails to parse.
        for line in tail.split(separator: 0x0A).reversed() where line.range(of: marker) != nil {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = json["type"] as? String, type == "user" || type == "permission-mode",
                  let mode = PermissionMode(raw: json["permissionMode"] as? String)
            else { continue }
            if type == "user", let since {
                guard let stamp = (json["timestamp"] as? String).flatMap(formatter.date(from:)),
                      stamp >= since.addingTimeInterval(-startSlack) else { return nil }
            }
            return mode
        }
        return nil
    }

    /// `<root>/projects/<folder>/<id>.jsonl` → `<root>`; nil for any other path.
    static func configRoot(ofTranscript path: String) -> URL? {
        let url = URL(filePath: path)
        let projects = url.deletingLastPathComponent().deletingLastPathComponent()
        guard url.pathExtension == "jsonl", projects.lastPathComponent == "projects" else { return nil }
        return projects.deletingLastPathComponent()
    }
}
