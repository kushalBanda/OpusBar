import Foundation
import OpusBarWire

/// One reset worth a notification: a plan window with some use, renewing at `date`.
public struct LimitResetNotice: Equatable, Sendable {
    /// Stable per account and window, so a newer reading replaces the scheduled one.
    public var id: String
    public var date: Date
    public var title: String
    public var body: String
}

/// Which plan windows get a notification when they renew: every window with some use and a known reset
/// time still ahead, for accounts the user has not muted. A window with nothing spent has nothing to give back.
public enum LimitResetPlanner {
    public static let identifierPrefix = "limit."

    public static func plan(_ limits: [UsageLimits], muted: Set<String>, enabled: Bool, now: Date) -> [LimitResetNotice] {
        guard enabled else { return [] }
        let named = Dictionary(grouping: limits, by: \.agent).mapValues { $0.count > 1 }
        return limits.filter { !muted.contains($0.id) }.flatMap { limits in
            limits.current(at: now).compactMap { window -> LimitResetNotice? in
                guard window.usedPercent > 0, let resets = window.resetsAt, resets > now else { return nil }
                // Several accounts of one agent: name the account, by the part of its email before the @.
                let name = limits.label.map { $0.split(separator: "@").first.map(String.init) ?? $0 }
                let account = named[limits.agent] == true ? name.map { " (\($0))" } ?? "" : ""
                return LimitResetNotice(
                    id: identifierPrefix + limits.id + "." + window.id, date: resets,
                    title: "\(limits.agent.displayName) limit reset",
                    body: "Your \(window.label.lowercasedFirst) limit\(account) is back to 100%.")
            }
        }
        .sorted { $0.date < $1.date }
    }
}

private extension String {
    /// "Week" reads "week" mid-sentence; "5 h" and "Opus week" stay as they are.
    var lowercasedFirst: String {
        guard let first, first.isUppercase, dropFirst().allSatisfy({ !$0.isUppercase }) else { return self }
        return first.lowercased() + dropFirst()
    }
}
