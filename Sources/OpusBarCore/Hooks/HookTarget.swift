import Foundation
import OpusBarWire

/// One thing OpusBar can connect: a Claude profile's `settings.json`, Codex's `hooks.json`, or the
/// `opusbar.ts` extension in pi's or OMP's extensions folder.
public struct HookTarget: Equatable, Sendable, Identifiable {
    public var agent: AgentKind
    /// The folder shown to the user (profile root, or Codex home).
    public var root: URL
    public var fileURL: URL
    public var events: [HookEventName]
    public var async: Bool
    /// Set for Claude profiles; nil for Codex.
    public var claudeOrigin: ClaudeProfile.Origin?
    /// OMP named profile (`omp --profile <name>`), nil for the default one.
    public var profile: String? = nil
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

    /// What the pi/OMP extension sends. No needs-you: pi has no permission prompts.
    public static let piFamilyEvents: [HookEventName] = [
        .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .stop, .stopFailure, .sessionEnd,
    ]

    /// Agent folders whose `extensions/` pi or OMP load, that exist (the agent ran here):
    /// - pi: `PI_CODING_AGENT_DIR` from OpusBar's own environment, or `~/.pi/agent`.
    /// - OMP: `PI_CODING_AGENT_DIR`, or `~/<PI_CONFIG_DIR or .omp>/agent`, plus every named profile's
    ///   `~/<config>/profiles/<name>/agent`.
    public static func piFamily(_ agent: AgentKind, environment: [String: String]) -> [HookTarget] {
        let home = ClaudeConfigPaths.homeDirectory(environment: environment)
        let override = environment["PI_CODING_AGENT_DIR"].flatMap { SessionRecordReader.expand($0, home: home, relativeTo: nil) }
        var dirs: [(URL, String?)]
        switch agent {
        case .pi:
            dirs = [(override ?? home.appending(path: ".pi/agent", directoryHint: .isDirectory), nil)]
        case .omp:
            let config = SessionRecordReader.ompConfigRoot(home: home, environment: environment)
            dirs = [(override ?? config.appending(path: "agent", directoryHint: .isDirectory), nil)]
            let profiles = config.appending(path: "profiles", directoryHint: .isDirectory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: profiles.path)) ?? []
            dirs += names.filter { !$0.hasPrefix(".") }.sorted()
                .map { (profiles.appending(path: "\($0)/agent", directoryHint: .isDirectory), $0) }
        case .claude, .codex:
            return []
        }
        return dirs.filter { FileManager.default.fileExists(atPath: $0.0.path) }.map { dir, profile in
            HookTarget(agent: agent, root: dir.standardizedFileURL,
                       fileURL: dir.appending(path: "extensions/\(PiExtensionInstaller.fileName)"),
                       events: piFamilyEvents, async: true, claudeOrigin: nil, profile: profile)
        }
    }

    /// pi and OMP get an extension file; Claude and Codex a hooks entry.
    public var isExtension: Bool { agent == .pi || agent == .omp }

    public func status(paths: OpusBarPaths) -> HookInstaller.Status {
        isExtension ? extensionInstaller(paths: paths).status() : installer(paths: paths).status()
    }

    @discardableResult
    public func install(paths: OpusBarPaths, hookSource: URL) throws -> HookInstaller.Status {
        let hooks = installer(paths: paths)
        guard isExtension else { return try hooks.install(hookSource: hookSource) }
        return try extensionInstaller(paths: paths).install(hookSource: hookSource, installBinary: hooks.installBinary(from:))
    }

    @discardableResult
    public func uninstall(paths: OpusBarPaths) throws -> HookInstaller.Status {
        isExtension ? try extensionInstaller(paths: paths).uninstall() : try installer(paths: paths).uninstall()
    }

    public func extensionInstaller(paths: OpusBarPaths) -> PiExtensionInstaller {
        PiExtensionInstaller(agent: agent, fileURL: fileURL, hookBinary: paths.hookBinary)
    }

    /// Claude entries omit `--agent` (M1 compatible: no agent means Claude Code).
    public var hookArguments: [String] { agent == .claude ? [] : ["--agent", agent.rawValue] }

    public func installer(paths: OpusBarPaths) -> HookInstaller {
        let name = root.path.split(separator: "/").joined(separator: "-")
        return HookInstaller(settingsURL: fileURL, events: events, hookBinary: paths.hookBinary, hookArguments: hookArguments,
                             backupsDir: paths.backupsDir.appending(path: "\(agent.rawValue)-\(name)", directoryHint: .isDirectory),
                             async: async)
    }
}
