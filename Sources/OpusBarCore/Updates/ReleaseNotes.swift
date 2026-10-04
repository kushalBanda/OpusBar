import Foundation

/// What the card after an update says: a version and its headline changes.
public struct WhatsNew: Codable, Equatable, Sendable {
    public var version: String
    public var highlights: [String]

    public init(version: String, highlights: [String]) {
        self.version = version
        self.highlights = highlights
    }
}

/// Turns a GitHub release body (the changelog section: a bullet per change) into short plain lines.
public enum ReleaseNotes {
    public static let fallback = "Fixes and improvements."

    /// Up to `limit` bullet lines with the markdown taken out; the fallback line when there are none.
    public static func highlights(from body: String, limit: Int = 4) -> [String] {
        let lines = body.split(whereSeparator: \.isNewline).compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
            let text = plain(String(line.dropFirst(2)))
            return text.isEmpty ? nil : text
        }
        return lines.isEmpty ? [fallback] : Array(lines.prefix(limit))
    }

    /// Links keep their text; bold, italics and code lose their marks.
    static func plain(_ markdown: String) -> String {
        var text = markdown
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for mark in ["**", "__", "`"] { text = text.replacingOccurrences(of: mark, with: "") }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
