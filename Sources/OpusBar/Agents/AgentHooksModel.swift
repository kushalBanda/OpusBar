import AppKit
import Observation
import OpusBarCore
import OpusBarWire

/// Everything OpusBar can connect (Claude profiles, Codex, pi, OMP) and its status, for Settings.
/// Install and uninstall run only on a user click.
@MainActor @Observable
final class AgentHooksModel {
    struct Row: Identifiable, Equatable {
        let target: HookTarget
        var status: HookInstaller.Status
        var id: String { target.id }
    }

    private(set) var rows: [Row] = []
    private(set) var lastError: String?

    @ObservationIgnored private let paths: OpusBarPaths
    @ObservationIgnored private let environment: [String: String]
    @ObservationIgnored private let defaults: UserDefaults

    init(paths: OpusBarPaths, environment: [String: String] = ProcessInfo.processInfo.environment,
         defaults: UserDefaults = .standard) {
        self.paths = paths
        self.environment = environment
        self.defaults = defaults
        refresh()
    }

    var userAddedFolders: [String] { defaults.stringArray(forKey: ClaudeProfiles.userDefaultsKey) ?? [] }

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
        let targets = ClaudeProfiles.all(environment: environment, userAdded: userAddedFolders).map(HookTarget.claude)
            + [HookTarget.codex(environment: environment)].compactMap { $0 }
            + HookTarget.piFamily(.pi, environment: environment) + HookTarget.piFamily(.omp, environment: environment)
        rows = targets.map { Row(target: $0, status: $0.status(paths: paths)) }
    }

    func install(_ target: HookTarget) {
        run(target) { try target.install(paths: self.paths, hookSource: Self.bundledHook()) }
    }

    func uninstall(_ target: HookTarget) {
        run(target) { try target.uninstall(paths: self.paths) }
    }

    func addClaudeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = ClaudeConfigPaths.homeDirectory(environment: environment)
        panel.message = "Choose a Claude config folder (the one that holds settings.json and projects/)."
        panel.prompt = "Add Profile"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var folders = userAddedFolders
        if !folders.contains(url.path) { folders.append(url.path) }
        defaults.set(folders, forKey: ClaudeProfiles.userDefaultsKey)
        refresh()
    }

    /// pi/OMP session folders the user added, so discovery finds sessions kept outside the defaults.
    func piFamilyFolders(for agent: AgentKind) -> [String] { PiFamilyFolders.folders(for: agent, defaults: defaults) }

    func addPiFamilyFolder(for agent: AgentKind) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = ClaudeConfigPaths.homeDirectory(environment: environment)
        panel.message = "Choose the folder where \(agent.displayName) keeps its session files."
        panel.prompt = "Add Folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var folders = piFamilyFolders(for: agent)
        if !folders.contains(url.path) { folders.append(url.path) }
        defaults.set(folders, forKey: PiFamilyFolders.key(for: agent))
        folderRevision += 1
    }

    func removePiFamilyFolder(_ path: String, for agent: AgentKind) {
        defaults.set(piFamilyFolders(for: agent).filter { $0 != path }, forKey: PiFamilyFolders.key(for: agent))
        folderRevision += 1
    }

    /// Bumped when pi/OMP folders change, so the pane re-reads them.
    private(set) var folderRevision = 0

    func removeClaudeFolder(_ target: HookTarget) {
        defaults.set(userAddedFolders.filter { URL(fileURLWithPath: $0).standardizedFileURL != target.root },
                     forKey: ClaudeProfiles.userDefaultsKey)
        refresh()
    }

    private func run(_ target: HookTarget, _ action: () throws -> HookInstaller.Status) {
        do {
            _ = try action()
            lastError = nil
        } catch HookInstaller.InstallError.unreadable(let reason) where target.isExtension {
            lastError = "\(reason) in \(target.fileURL.deletingLastPathComponent().path), and it isn't OpusBar's. Rename or remove it, then connect again."
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
