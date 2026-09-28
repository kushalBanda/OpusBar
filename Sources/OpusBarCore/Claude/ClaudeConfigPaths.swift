import Foundation

/// Where Claude Code keeps its settings and transcripts, matching Claude's own profile boundary.
public enum ClaudeConfigPaths {
    public static let configDirectoryEnvironmentKey = "CLAUDE_CONFIG_DIR"

    /// `CLAUDE_CONFIG_DIR` is one literal directory; empty or unset means `~/.claude`.
    public static func configRoot(environment: [String: String], workingDirectory: URL? = nil) -> URL {
        if let configured = nonempty(environment[configDirectoryEnvironmentKey]) {
            return directoryURL(configured, workingDirectory: workingDirectory)
        }
        return homeDirectory(environment: environment, workingDirectory: workingDirectory)
            .appending(path: ".claude", directoryHint: .isDirectory)
    }

    /// The user settings file the hook installer merges into (M2).
    public static func settingsURL(environment: [String: String], workingDirectory: URL? = nil) -> URL {
        configRoot(environment: environment, workingDirectory: workingDirectory).appending(path: "settings.json")
    }

    /// Session transcripts, one folder per project (usage scanning, M4).
    public static func projectsRoot(environment: [String: String], workingDirectory: URL? = nil) -> URL {
        configRoot(environment: environment, workingDirectory: workingDirectory)
            .appending(path: "projects", directoryHint: .isDirectory)
    }

    public static func homeDirectory(environment: [String: String], workingDirectory: URL? = nil) -> URL {
        if let home = nonempty(environment["HOME"]) {
            return directoryURL(home, workingDirectory: workingDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    private static func nonempty(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    /// Claude receives the variable unexpanded: only a leading `/` is absolute, `~` stays literal,
    /// and relative paths resolve against the working directory.
    private static func directoryURL(_ path: String, workingDirectory: URL?) -> URL {
        if path.hasPrefix("/") {
            return URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
        }
        let base = workingDirectory ?? URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        return base.appending(path: path, directoryHint: .isDirectory).standardizedFileURL
    }
}
