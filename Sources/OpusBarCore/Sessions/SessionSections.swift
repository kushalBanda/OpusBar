import Foundation

/// How the dropdown groups sessions. Order inside a section is stable (never by state), so a card
/// doesn't jump under the pointer each time its session flips between thinking and working.
/// A card moves only when it changes section.
public struct SessionSections: Equatable, Sendable {
    /// Needs you and error: waiting longest first.
    public var loud: [Session]
    /// Thinking, working, done: newest session first.
    public var active: [Session]
    /// Idle: newest session first.
    public var idle: [Session]

    /// From this many sessions on, the list shows section headers and folds Idle into one row.
    public static let groupingThreshold = 6

    public init(_ sessions: [Session]) {
        let newestFirst: (Session, Session) -> Bool = { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) }
        loud = sessions.filter { $0.state == .needsAttention || $0.state == .error }
            .sorted { ($0.stateSince, $0.id) < ($1.stateSince, $1.id) }
        active = sessions.filter { $0.state == .thinking || $0.state == .working || $0.state == .done }
            .sorted(by: newestFirst)
        idle = sessions.filter { $0.state == .idle }.sorted(by: newestFirst)
    }

    public var count: Int { loud.count + active.count + idle.count }
    public var isGrouped: Bool { count >= Self.groupingThreshold }

    /// "3 need you · 8 active · 9 idle"; empty parts are left out.
    public var summary: String {
        guard count > 0 else { return "No sessions" }
        let needs = loud.filter { $0.state == .needsAttention }.count
        let errors = loud.count - needs
        let parts = [
            needs > 0 ? "\(needs) need\(needs == 1 ? "s" : "") you" : nil,
            errors > 0 ? "\(errors) error\(errors == 1 ? "" : "s")" : nil,
            active.isEmpty ? nil : "\(active.count) active",
            idle.isEmpty ? nil : "\(idle.count) idle",
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}
