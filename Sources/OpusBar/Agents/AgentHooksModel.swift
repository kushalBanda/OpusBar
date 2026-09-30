import AppKit
import Observation
import OpusBarCore
import OpusBarWire

/// Everything OpusBar can connect (Claude profiles, Codex) and its status, for Settings.
/// Install and uninstall run only on a user click.
@MainActor @Observable
final class AgentHooksModel {
    struct Row: Identifiable, Equatable {
        let target: HookTarget
        var status: HookInstaller.Status
        var id: String { target.id }
    }

    private(set) var rows: [Row] = []
    /// The email each Claude profile is signed in with, by target id.
    private(set) var emails: [String: String] = [:]
    private(set) var lastError: String?

    @ObservationIgnored private let paths: OpusBarPaths
    @ObservationIgnored private let environment: [String: String]
    @ObservationIgnored private let defaults: UserDefaults

    init(paths: OpusBarPaths, environment: [String: String] = ProcessInfo.processInfo.environment,
         defaults: UserDefaults = .standard) {
        self.paths = paths
        self.environment = environment
        self.defaults = defaults
        // A new app version carries a new hook: the connected agents run the copy, so bring it up to date.
        do {
            try HookInstaller.refreshBinary(paths.hookBinary, from: Self.bundledHook())
        } catch {
            NSLog("OpusBar: hook refresh failed: \(error)")
        }
        refresh()
    }

    var userAddedFolders: [String] { defaults.stringArray(forKey: ClaudeProfiles.userDefaultsKey) ?? [] }
    var userAddedCodexFolders: [String] { defaults.stringArray(forKey: CodexHomes.userDefaultsKey) ?? [] }

    func rows(for agent: AgentKind) -> [Row] { rows.filter { $0.target.agent == agent } }

    /// Agents with at least one connected hooks file.
    var connectedAgents: Set<AgentKind> { Set(rows.filter { $0.status == .installed }.map(\.target.agent)) }

    /// At least one hooks file has OpusBar installed.
    var anyConnected: Bool { rows.contains { $0.status == .installed } }
    /// At least one agent is present and could be connected.
    var anyConnectable: Bool {
        rows.contains { if case .unreadable = $0.status { false } else { true } }
    }

    func backupsDirectory(for target: HookTarget) -> URL { target.installer(paths: paths).backupsDir }

    func refresh() {
        let profiles = ClaudeProfiles.all(environment: environment, userAdded: userAddedFolders)
        let targets = profiles.map(HookTarget.claude)
            + CodexHomes.all(environment: environment, userAdded: userAddedCodexFolders).map(HookTarget.codex)
        rows = targets.map { Row(target: $0, status: $0.status(paths: paths)) }
        let home = ClaudeConfigPaths.homeDirectory(environment: environment)
        var emails: [String: String] = [:]
        for profile in profiles {
            let email = profile.accountFiles(home: home).lazy
                .compactMap { (try? Data(contentsOf: $0, options: .mappedIfSafe)).flatMap(ClaudeCodeLimits.email) }.first
            if let email { emails[HookTarget.claude(profile).id] = email }
        }
        self.emails = emails
    }

    func install(_ target: HookTarget) {
        run(target) { try target.install(paths: self.paths, hookSource: Self.bundledHook()) }
    }

    func uninstall(_ target: HookTarget) {
        run(target) { try target.uninstall(paths: self.paths) }
    }

    func addClaudeFolder() {
        addFolder(key: ClaudeProfiles.userDefaultsKey, prompt: "Add Profile",
                  message: "Choose a Claude config folder (the one that holds settings.json and projects/).")
    }

    func addCodexFolder() {
        addFolder(key: CodexHomes.userDefaultsKey, prompt: "Add Folder",
                  message: "Choose a Codex home folder (the one that holds config.toml and sessions/).")
    }

    /// Forgets a folder the user added (Claude profile or Codex home).
    func removeFolder(_ target: HookTarget) {
        let key = target.agent == .claude ? ClaudeProfiles.userDefaultsKey : CodexHomes.userDefaultsKey
        let folders = defaults.stringArray(forKey: key) ?? []
        defaults.set(folders.filter { URL(fileURLWithPath: $0).standardizedFileURL != target.root }, forKey: key)
        refresh()
    }

    private func addFolder(key: String, prompt: String, message: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = ClaudeConfigPaths.homeDirectory(environment: environment)
        panel.message = message
        panel.prompt = prompt
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var folders = defaults.stringArray(forKey: key) ?? []
        if !folders.contains(url.path) { folders.append(url.path) }
        defaults.set(folders, forKey: key)
        refresh()
    }

    private func run(_ target: HookTarget, _ action: () throws -> HookInstaller.Status) {
        do {
            _ = try action()
            lastError = nil
        } catch HookInstaller.InstallError.unreadable(let reason) {
            lastError = "The hooks file can't be read (\(reason)). Fix it by hand; OpusBar won't touch it."
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    /// The hook shipped with the app: `Contents/Helpers/opusbar-hook`, or next to the executable under `swift run`.
    static func bundledHook() -> URL {
        let helper = Bundle.main.bundleURL.appending(path: "Contents/Helpers/opusbar-hook")
        if FileManager.default.isExecutableFile(atPath: helper.path) { return helper }
        return Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "opusbar-hook") ?? helper
    }

    /// Every known Claude profile's `.claude.json` (account and cached plan limits). Thread-safe.
    nonisolated static func claudeAccountFiles(environment: [String: String]) -> [ClaudeAccountFiles] {
        let userAdded = UserDefaults.standard.stringArray(forKey: ClaudeProfiles.userDefaultsKey) ?? []
        let home = ClaudeConfigPaths.homeDirectory(environment: environment)
        return ClaudeProfiles.all(environment: environment, userAdded: userAdded)
            .map { ClaudeAccountFiles(root: $0.root, files: $0.accountFiles(home: home)) }
    }

    /// Every known Codex home, the folders the user added included. Thread-safe.
    nonisolated static func codexHomes(environment: [String: String]) -> [CodexHome] {
        let userAdded = UserDefaults.standard.stringArray(forKey: CodexHomes.userDefaultsKey) ?? []
        return CodexHomes.all(environment: environment, userAdded: userAdded)
    }

    /// Project roots of every known Claude profile, for discovery. Thread-safe: reads UserDefaults directly.
    nonisolated static func claudeProjectRoots(environment: [String: String]) -> [URL] {
        let userAdded = UserDefaults.standard.stringArray(forKey: ClaudeProfiles.userDefaultsKey) ?? []
        let home = ClaudeConfigPaths.homeDirectory(environment: environment)
        let roots = SessionDiscovery.defaultClaudeProjectRoots(home: home, environment: environment)
            + ClaudeProfiles.all(environment: environment, userAdded: userAdded).map(\.projectsRoot)
        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted && FileManager.default.fileExists(atPath: $0.path) }
    }
}
