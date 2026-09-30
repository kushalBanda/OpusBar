import Foundation

/// A Codex home: the folder Codex keeps its hooks, config and session logs in. One per account, since
/// Codex signs in per home (`CODEX_HOME=~/.codex-work codex`).
public struct CodexHome: Equatable, Hashable, Sendable, Identifiable {
    public var root: URL
    public var origin: ClaudeProfile.Origin
    public var id: String { root.path }
    public var hooksURL: URL { root.appending(path: "hooks.json") }
    /// `sessions/` and `archived_sessions/`. Codex moves a rollout to the archive unchanged, so a reply
    /// found in both counts once (same response id).
    public var sessionRoots: [URL] {
        ["sessions", "archived_sessions"].map { root.appending(path: $0, directoryHint: .isDirectory) }
    }

    public init(root: URL, origin: ClaudeProfile.Origin) {
        self.root = root.standardizedFileURL
        self.origin = origin
    }
}

public enum CodexHomes {
    public static let userDefaultsKey = "codexHomeFolders"

    /// Known homes that exist on disk: `~/.codex`, the app's own `$CODEX_HOME`, `~/.codex-<name>` folders
    /// Codex has used, then folders the user added. Without duplicates. Nothing inside is read here.
    public static func all(environment: [String: String], userAdded: [String],
                           fileManager: FileManager = .default) -> [CodexHome] {
        let home = ClaudeConfigPaths.homeDirectory(environment: environment)
        var candidates = [CodexHome(root: home.appending(path: ".codex", directoryHint: .isDirectory), origin: .standard)]
        if let configured = environment["CODEX_HOME"], configured.hasPrefix("/") {
            candidates.append(CodexHome(root: URL(fileURLWithPath: configured, isDirectory: true), origin: .environment))
        }
        candidates += detected(home: home, fileManager: fileManager)
        candidates += userAdded.filter { $0.hasPrefix("/") }.map {
            CodexHome(root: URL(fileURLWithPath: $0, isDirectory: true), origin: .userAdded)
        }
        var seen = Set<String>()
        return candidates.filter { codex in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: codex.root.path, isDirectory: &isDirectory) && isDirectory.boolValue
                && seen.insert(codex.root.resolvingSymlinksInPath().path).inserted
        }
    }

    /// `~/.codex-<name>` folders Codex has run in (they hold `sessions/` or `config.toml`). Other tools'
    /// `~/.codex-*` folders have neither and are left out.
    static func detected(home: URL, fileManager: FileManager) -> [CodexHome] {
        let names = (try? fileManager.contentsOfDirectory(atPath: home.path)) ?? []
        return names.filter { $0.hasPrefix(".codex-") }.sorted().compactMap { name in
            let root = home.appending(path: name, directoryHint: .isDirectory)
            guard ["sessions", "config.toml"].contains(where: { fileManager.fileExists(atPath: root.appending(path: $0).path) })
            else { return nil }
            return CodexHome(root: root, origin: .detected)
        }
    }
}

/// What to call an account's folder when nothing better is known: `~/.codex-work` is "codex-work".
public enum AccountFolder {
    public static func name(_ path: String) -> String {
        let last = URL(fileURLWithPath: path).lastPathComponent
        return last.hasPrefix(".") ? String(last.dropFirst()) : last
    }
}
