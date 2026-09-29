import Foundation

/// The Claude config roots OpusBar knows about: `~/.claude`, `~/.config/claude`, the app's own
/// `CLAUDE_CONFIG_DIR`, and folders the user added. Other processes' environments are never read.
public struct ClaudeProfile: Equatable, Hashable, Sendable, Identifiable {
    public enum Origin: String, Sendable { case standard, environment, userAdded }

    public var root: URL
    public var origin: Origin
    public var id: String { root.path }
    public var settingsURL: URL { root.appending(path: "settings.json") }
    public var projectsRoot: URL { root.appending(path: "projects", directoryHint: .isDirectory) }

    public init(root: URL, origin: Origin) {
        self.root = root.standardizedFileURL
        self.origin = origin
    }

}

public enum ClaudeProfiles {
    public static let userDefaultsKey = "claudeProfileFolders"

    /// Known profiles that exist on disk, standard first, without duplicates.
    public static func all(environment: [String: String], userAdded: [String],
                           fileManager: FileManager = .default) -> [ClaudeProfile] {
        let home = ClaudeConfigPaths.homeDirectory(environment: environment)
        var candidates = [
            ClaudeProfile(root: home.appending(path: ".claude", directoryHint: .isDirectory), origin: .standard),
            ClaudeProfile(root: home.appending(path: ".config/claude", directoryHint: .isDirectory), origin: .standard),
        ]
        if let configured = environment[ClaudeConfigPaths.configDirectoryEnvironmentKey], !configured.isEmpty {
            candidates.append(ClaudeProfile(root: ClaudeConfigPaths.configRoot(environment: environment), origin: .environment))
        }
        candidates += userAdded.filter { $0.hasPrefix("/") }.map {
            ClaudeProfile(root: URL(fileURLWithPath: $0, isDirectory: true), origin: .userAdded)
        }
        var seen = Set<String>()
        return candidates.filter { profile in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: profile.root.path, isDirectory: &isDirectory) && isDirectory.boolValue
                && seen.insert(profile.root.resolvingSymlinksInPath().path).inserted
        }
    }
}
