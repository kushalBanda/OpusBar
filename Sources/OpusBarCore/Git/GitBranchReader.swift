import Foundation

/// Reads the current branch straight from `.git/HEAD`. Never runs a git process.
public enum GitBranchReader {
    /// Walks up from `cwd` to the nearest `.git`. Detached HEAD gives a 7-character sha. Nil outside a repo.
    public static func branch(atPath cwd: String) -> String? {
        guard let gitDir = gitDirectory(from: URL(fileURLWithPath: cwd)),
              let head = try? String(contentsOf: gitDir.appending(path: "HEAD"), encoding: .utf8)
        else { return nil }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: ") {
            let ref = line.dropFirst(5)
            return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst(11)) : String(ref)
        }
        return line.isEmpty ? nil : String(line.prefix(7))
    }

    /// A `.git` directory, or the directory a worktree's `.git` file points at (`gitdir: <path>`).
    static func gitDirectory(from start: URL) -> URL? {
        let fm = FileManager.default
        var dir = start.standardizedFileURL.path
        while true {
            let git = (dir as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git, isDirectory: &isDir) {
                if isDir.boolValue { return URL(fileURLWithPath: git) }
                guard let text = try? String(contentsOfFile: git, encoding: .utf8),
                      let line = text.split(separator: "\n").first, line.hasPrefix("gitdir: ")
                else { return nil }
                let target = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                let resolved = target.hasPrefix("/") ? target : (dir as NSString).appendingPathComponent(target)
                return URL(fileURLWithPath: resolved).standardizedFileURL
            }
            // "/" is its own parent on NSString paths, so this ends at the root.
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return nil }
            dir = parent
        }
    }
}
