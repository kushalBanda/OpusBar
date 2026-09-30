import Foundation
import OpusBarWire

/// One reset worth a notification: a plan window with some use, renewing at `date`.
public struct LimitResetNotice: Equatable, Sendable {
    /// Stable per account and window, so a newer reading replaces the scheduled one.
    public var id: String
    public var date: Date
    public var title: String
    public var body: String

    public init(id: String, date: Date, title: String, body: String) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
    }
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
                let account = accountName(limits, named: named[limits.agent] == true)
                return LimitResetNotice(
                    id: identifierPrefix + limits.id + "." + window.id, date: resets,
                    title: "\(limits.agent.displayName) limit reset",
                    body: "Your \(window.label.lowercasedFirst) limit\(account) is back to 100%.")
            }
        }
        .sorted { $0.date < $1.date }
    }

    /// " (kushal)" when an agent has several accounts: the part of the label before the @. Empty otherwise.
    static func accountName(_ limits: UsageLimits, named: Bool) -> String {
        guard named, let label = limits.label else { return "" }
        return " (\(label.split(separator: "@").first.map(String.init) ?? label))"
    }
}

/// A warning that a plan window is nearly spent, and the thresholds it settles, so none repeats.
public struct LimitWarning: Equatable, Sendable {
    public var notice: LimitResetNotice
    /// Keys to remember as sent: this threshold and every lower one, for this window's period.
    public var keys: [String]

    public init(notice: LimitResetNotice, keys: [String]) {
        self.notice = notice
        self.keys = keys
    }
}

/// Which plan windows get a "nearly used" notification now: a window at or past 80 % or 95 % used, once per
/// threshold per window period (the key holds the reset time, so the next period warns again). Only the
/// highest threshold crossed is sent: a jump from 70 % to 96 % warns once, at 95 %.
public enum LimitWarningPlanner {
    public static let thresholds: [Double] = [80, 95]
    public static let identifierPrefix = "limitwarn."

    public static func due(_ limits: [UsageLimits], muted: Set<String>, enabled: Bool, sent: Set<String>,
                           now: Date) -> [LimitWarning] {
        guard enabled else { return [] }
        let named = Dictionary(grouping: limits, by: \.agent).mapValues { $0.count > 1 }
        return limits.filter { !muted.contains($0.id) }.flatMap { limits in
            limits.current(at: now).compactMap { window -> LimitWarning? in
                let crossed = thresholds.filter { window.usedPercent >= $0 }
                guard let top = crossed.last else { return nil }
                let keys = crossed.map { key(limits, window, threshold: $0) }
                guard !sent.contains(keys[keys.count - 1]) else { return nil }
                let account = LimitResetPlanner.accountName(limits, named: named[limits.agent] == true)
                let resets = window.resetsAt.map { " It resets in \(UsageFormat.countdown(to: $0, now: now))." } ?? ""
                return LimitWarning(
                    notice: LimitResetNotice(
                        id: keys[keys.count - 1], date: now,
                        title: "\(limits.agent.displayName) limit \(Int(top))% used",
                        body: "Your \(window.label.lowercasedFirst) limit\(account) is \(UsageFormat.percent(window.usedFraction)) used.\(resets)"),
                    keys: keys)
            }
        }
    }

    /// Sent keys still worth keeping: those whose window has not renewed yet.
    public static func unexpired(_ sent: Set<String>, now: Date) -> Set<String> {
        sent.filter { key in
            guard let epoch = key.split(separator: ".").last.flatMap({ Double($0) }) else { return false }
            return Date(timeIntervalSince1970: epoch) > now
        }
    }

    static func key(_ limits: UsageLimits, _ window: UsageLimitWindow, threshold: Double) -> String {
        // No reset time: the key never expires, and the window warns once until it gets one.
        let period = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "\(Int.max)"
        return identifierPrefix + limits.id + "." + window.id + ".\(Int(threshold))." + period
    }
}

private extension String {
    /// "Week" reads "week" mid-sentence; "5 h" and "Opus week" stay as they are.
    var lowercasedFirst: String {
        guard let first, first.isUppercase, dropFirst().allSatisfy({ !$0.isUppercase }) else { return self }
        return first.lowercased() + dropFirst()
    }
}
