import Foundation
import OpusBarWire

/// One thing OpusBar can connect: a Claude profile's `settings.json` or Codex's `hooks.json`.
public struct HookTarget: Equatable, Sendable, Identifiable {
    public var agent: AgentKind
    /// The folder shown to the user (profile root, or Codex home).
    public var root: URL
    public var fileURL: URL
    public var events: [HookEventName]
    public var async: Bool
    /// Set for Claude profiles; nil for Codex.
    public var claudeOrigin: ClaudeProfile.Origin?
    public var id: String { "\(agent.rawValue):\(fileURL.path)" }

    /// Events Codex 0.155 fires that the reducer uses. Codex has no Notification or StopFailure.
    public static let codexEvents: [HookEventName] = [
        .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .permissionRequest,
        .subagentStart, .subagentStop, .stop, .sessionEnd,
    ]

    public static func claude(_ profile: ClaudeProfile) -> HookTarget {
        HookTarget(agent: .claude, root: profile.root, fileURL: profile.settingsURL,
                   events: HookEventName.subscribed, async: true, claudeOrigin: profile.origin)
    }

    /// `$CODEX_HOME/hooks.json`, or `~/.codex/hooks.json`. Nil when Codex has never run here.
    public static func codex(environment: [String: String]) -> HookTarget? {
        let home = ClaudeConfigPaths.homeDirectory(environment: environment)
        let codexHome = environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
            ?? home.appending(path: ".codex", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: codexHome.path) else { return nil }
        return HookTarget(agent: .codex, root: codexHome.standardizedFileURL, fileURL: codexHome.appending(path: "hooks.json"),
                          events: codexEvents, async: false, claudeOrigin: nil)
    }

    public func status(paths: OpusBarPaths) -> HookInstaller.Status { installer(paths: paths).status() }

    @discardableResult
    public func install(paths: OpusBarPaths, hookSource: URL) throws -> HookInstaller.Status {
        try installer(paths: paths).install(hookSource: hookSource)
    }

    @discardableResult
    public func uninstall(paths: OpusBarPaths) throws -> HookInstaller.Status { try installer(paths: paths).uninstall() }

    /// Claude entries omit `--agent` (M1 compatible: no agent means Claude Code).
    public var hookArguments: [String] { agent == .claude ? [] : ["--agent", agent.rawValue] }

    public func installer(paths: OpusBarPaths) -> HookInstaller {
        let name = root.path.split(separator: "/").joined(separator: "-")
        return HookInstaller(settingsURL: fileURL, events: events, hookBinary: paths.hookBinary, hookArguments: hookArguments,
                             backupsDir: paths.backupsDir.appending(path: "\(agent.rawValue)-\(name)", directoryHint: .isDirectory),
                             async: async)
    }
}
