import Foundation

/// What a host window's title may hold to show it is the session's window. Most apps put the folder
/// in the title (VS Code: "file — folder — Cursor"; terminals: "folder — zsh").
public struct WindowNeedles: Hashable, Sendable {
    public var folder: String
    /// The name the user gave the session; Claude Code also sets it as the terminal title.
    public var title: String?
    public var branch: String?

    public init(folder: String, title: String? = nil, branch: String? = nil) {
        self.folder = folder
        self.title = title
        self.branch = branch
    }

    public init(_ session: Session) {
        self.init(folder: session.projectName, title: session.distinctTitle, branch: session.branch)
    }
}

/// Picks the window to raise from the host app's window titles. Pure, so the match rules are tested.
public enum WindowPicker {
    /// A window qualifies when its title holds the folder name or the session's own name; a branch name
    /// alone ("main") says too little. Among those, more matches win, then the earlier (front-most) window.
    /// No qualifying window gives nil: raising nothing is better than raising the wrong window.
    public static func pick(titles: [String], needles: WindowNeedles) -> Int? {
        let folder = needles.folder == "Unknown project" ? nil : needles.folder
        // Whole names only: folder "api" must not match a window for "api-server".
        func has(_ needle: String?, _ title: String) -> Bool {
            guard let needle, !needle.isEmpty else { return false }
            let pattern = #"(?<![\w.-])"# + NSRegularExpression.escapedPattern(for: needle) + #"(?![\w-])"#
            return title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        var best: (index: Int, score: Int)?
        for (index, title) in titles.enumerated() {
            guard has(folder, title) || has(needles.title, title) else { continue }
            let score = [folder, needles.title, needles.branch].filter { has($0, title) }.count
            if best == nil || score > best!.score { best = (index, score) }
        }
        return best?.index
    }
}
