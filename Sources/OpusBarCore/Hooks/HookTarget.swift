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
    /// How OpusBar found the folder.
    public var origin: ClaudeProfile.Origin
    public var id: String { "\(agent.rawValue):\(fileURL.path)" }

    /// Events Codex 0.155 fires that the reducer uses. Codex has no Notification or StopFailure.
    public static let codexEvents: [HookEventName] = [
        .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .permissionRequest,
        .subagentStart, .subagentStop, .stop, .sessionEnd,
    ]

    public static func claude(_ profile: ClaudeProfile) -> HookTarget {
        HookTarget(agent: .claude, root: profile.root, fileURL: profile.settingsURL,
                   events: HookEventName.subscribed, async: true, origin: profile.origin)
    }

    public static func codex(_ home: CodexHome) -> HookTarget {
        HookTarget(agent: .codex, root: home.root, fileURL: home.hooksURL, events: codexEvents, async: false,
                   origin: home.origin)
    }

    /// `$CODEX_HOME/hooks.json`, or `~/.codex/hooks.json`. Nil when Codex has never run here.
    public static func codex(environment: [String: String]) -> HookTarget? {
        let homes = CodexHomes.all(environment: environment, userAdded: [])
        return (homes.first { $0.origin == .environment } ?? homes.first { $0.origin == .standard }).map(codex)
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
                             async: async, statusLineRoot: agent == .claude ? root : nil)
    }
}
