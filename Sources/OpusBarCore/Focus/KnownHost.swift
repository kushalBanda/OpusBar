import Foundation
import OpusBarWire

/// A host app that OpusBar has an exact route into. Any other app still comes forward through `activateApp`.
/// One place to add the next terminal.
public enum KnownHost: Equatable, Sendable {
    case orca, iterm, terminalApp, ghostty, vscodeFamily

    /// Editors built on VS Code. Their integrated terminal sets `TERM_PROGRAM=vscode`; the names cover
    /// sessions found by discovery, which carry no environment.
    static let vscodeFamilyApps: Set<String> = ["Visual Studio Code", "Visual Studio Code - Insiders", "Cursor", "Windsurf",
                                                "VSCodium", "Positron", "Code - OSS", "Antigravity", "Kiro", "Trae", "Void"]

    /// nil for an app we have no special route for.
    public static func of(_ session: Session) -> KnownHost? {
        if session.host?.appName == "Orca" || session.term?.termProgram == "Orca" { return .orca }
        if session.host?.appPath?.hasSuffix("/iTerm.app") == true || session.term?.termProgram == "iTerm.app" { return .iterm }
        if session.host?.appPath?.hasSuffix("/Terminal.app") == true || session.term?.termProgram == "Apple_Terminal" {
            return .terminalApp
        }
        // Apps built on Ghostty (cmux) also set TERM_PROGRAM=ghostty; Ghostty's script would drive the real Ghostty.
        if session.host?.appPath?.hasSuffix("/Ghostty.app") == true
            || (session.term?.termProgram == "ghostty" && session.host?.appName?.lowercased().contains("ghostty") != false) {
            return .ghostty
        }
        if session.term?.termProgram == "vscode" || session.host?.appName.map(vscodeFamilyApps.contains) == true {
            return .vscodeFamily
        }
        return nil
    }
}
