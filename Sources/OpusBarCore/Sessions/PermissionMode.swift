import Foundation

/// How freely a session may act, from the hook payload's `permission_mode`. Claude Code switches it
/// with Shift+Tab; Codex sends the same field. A value OpusBar doesn't know yet keeps its raw name.
public enum PermissionMode: Equatable, Sendable {
    /// Asks before edits and commands. Claude's `default`.
    case manual
    case acceptEdits
    case plan
    case auto
    case dontAsk
    case bypassPermissions
    case other(String)

    public init?(raw: String?) {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case "default": self = .manual
        case "acceptEdits": self = .acceptEdits
        case "plan": self = .plan
        case "auto": self = .auto
        case "dontAsk": self = .dontAsk
        case "bypassPermissions": self = .bypassPermissions
        default: self = .other(raw)
        }
    }

    public var label: String {
        switch self {
        case .manual: "Manual"
        case .acceptEdits: "Accept edits"
        case .plan: "Plan"
        case .auto: "Auto"
        case .dontAsk: "Don't ask"
        case .bypassPermissions: "Bypass"
        case .other(let raw): Self.words(raw)
        }
    }

    /// Manual is the starting point; the card only names a mode the user switched to.
    public var isDefault: Bool { self == .manual }

    /// Skips every permission check: worth a warning tint, not just a label.
    public var isUnguarded: Bool { self == .bypassPermissions }

    /// `fullAccess` / `full-access` / `full_access` read as "Full access".
    static func words(_ raw: String) -> String {
        var spaced = ""
        for character in raw {
            if character == "-" || character == "_" {
                spaced.append(" ")
            } else if character.isUppercase, !spaced.isEmpty, spaced.last != " " {
                spaced.append(" ")
                spaced.append(contentsOf: character.lowercased())
            } else {
                spaced.append(spaced.isEmpty ? Character(character.uppercased()) : character)
            }
        }
        return spaced
    }
}
