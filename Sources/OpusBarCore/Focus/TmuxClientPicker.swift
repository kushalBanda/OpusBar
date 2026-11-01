import Foundation

/// A session inside tmux runs on a pane's tty, under the tmux server, which belongs to no app. The
/// terminal window the user sees is a tmux client. This finds the pane and the client that shows its session.
public enum TmuxClientPicker {
    /// `tmux list-panes -a -F` format: pane tty, pane id, session name.
    public static let panesFormat = "#{pane_tty}\t#{pane_id}\t#{session_name}"
    /// `tmux list-clients -F` format: client tty, client pid, attached session, last activity.
    public static let clientsFormat = "#{client_tty}\t#{client_pid}\t#{client_session}\t#{client_activity}"

    public struct Pick: Equatable, Sendable {
        public let paneId: String
        public let clientTty: String
        public let clientPid: Int32
    }

    /// The pane on `paneTty`, and the client to switch to it. A client already on the pane's session
    /// wins, the most recently active first; with none, the most recently active client of any session.
    public static func pick(paneTty: String, panes: String, clients: String) -> Pick? {
        guard let tty = TerminalScript.safeTty(paneTty),
              let pane = rows(panes, columns: 3).first(where: { $0[0] == tty }), isPaneId(pane[1]) else { return nil }
        let live = rows(clients, columns: 4).compactMap { row -> (tty: String, pid: Int32, session: String, activity: Int)? in
            guard let clientTty = TerminalScript.safeTty(row[0]), let pid = Int32(row[1]), pid > 1 else { return nil }
            return (clientTty, pid, row[2], Int(row[3]) ?? 0)
        }
        let onSession = live.filter { $0.session == pane[2] }
        guard let client = (onSession.isEmpty ? live : onSession).max(by: { $0.activity < $1.activity }) else { return nil }
        return Pick(paneId: pane[1], clientTty: client.tty, clientPid: client.pid)
    }

    /// `$TMUX` is `<socket path>,<server pid>,<session index>`. The socket names the server to ask;
    /// the pid finds the tmux binary that runs it. Paths with control characters are refused.
    public static func server(fromTmuxEnv tmux: String?) -> (socket: String, pid: Int32?)? {
        guard let tmux else { return nil }
        let parts = tmux.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let socket = parts.first, socket.hasPrefix("/"),
              !socket.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return (socket, parts.count > 1 ? Int32(parts[1]) : nil)
    }

    static func isPaneId(_ id: String) -> Bool {
        id.hasPrefix("%") && id.count > 1 && id.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func rows(_ text: String, columns: Int) -> [[String]] {
        text.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
            .filter { $0.count == columns }
    }
}
