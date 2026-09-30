import Foundation

/// Every file location OpusBar uses. The hook and the app both derive paths from here
/// so they always agree on the socket.
public struct OpusBarPaths: Sendable, Equatable {
    /// `sockaddr_un.sun_path` holds 104 bytes including the terminating NUL.
    public static let maxSocketPathBytes = 103

    public let home: URL
    public let supportDir: URL
    public let socket: URL
    public let hookBinary: URL
    public let backupsDir: URL
    /// Live plan limits from each Claude profile's status line, one file per profile.
    public let liveLimitsDir: URL

    public init(home: URL) {
        self.home = home
        supportDir = home.appending(path: "Library/Application Support/OpusBar", directoryHint: .isDirectory)
        let preferred = supportDir.appending(path: "events.sock")
        socket = preferred.path.utf8.count <= Self.maxSocketPathBytes
            ? preferred
            : home.appending(path: ".opusbar/events.sock")
        hookBinary = supportDir.appending(path: "bin/opusbar-hook")
        backupsDir = supportDir.appending(path: "backups", directoryHint: .isDirectory)
        liveLimitsDir = supportDir.appending(path: "limits", directoryHint: .isDirectory)
    }

    /// `limits/claude-Users-me-.claude.json` for `/Users/me/.claude`.
    public func liveLimitsFile(profileRoot: String) -> URL {
        let name = profileRoot.split(separator: "/").joined(separator: "-")
        return liveLimitsDir.appending(path: "claude-\(name).json")
    }

    /// Paths for the current user, preferring `$HOME`.
    public static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> OpusBarPaths {
        if let home = environment["HOME"], !home.isEmpty {
            return OpusBarPaths(home: URL(filePath: home, directoryHint: .isDirectory))
        }
        return OpusBarPaths(home: FileManager.default.homeDirectoryForCurrentUser)
    }
}
