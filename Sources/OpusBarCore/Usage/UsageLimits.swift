import Foundation
import OpusBarWire

/// A plan allowance and how much of it is spent, as the agent's own files report it.
public struct UsageLimitWindow: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case session, weekly, other
    }

    public var id: String
    public var kind: Kind
    /// How long the window lasts, when the file says.
    public var minutes: Int?
    /// A model the allowance is for; nil when it covers everything.
    public var scope: String?
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(id: String, kind: Kind, minutes: Int?, scope: String? = nil, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.kind = kind
        self.minutes = minutes
        self.scope = scope
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
    }

    public var usedFraction: Double { usedPercent / 100 }
    public var remainingFraction: Double { 1 - usedFraction }

    /// "5 h", "Week", "Opus week", "30 d".
    public var label: String {
        let base: String
        switch kind {
        case .session: base = minutes.map { $0 % 60 == 0 ? "\($0 / 60) h" : "\($0) min" } ?? "Session"
        case .weekly: base = "Week"
        case .other: base = minutes.map { $0 % 1440 == 0 ? "\($0 / 1440) d" : "\($0 / 60) h" } ?? "Limit"
        }
        guard let scope else { return base }
        return "\(scope) \(base.lowercased())"
    }

    static func kind(minutes: Int?) -> Kind {
        guard let minutes, minutes > 0 else { return .other }
        if minutes <= 12 * 60 { return .session }
        if (6 * 1440...8 * 1440).contains(minutes) { return .weekly }
        return .other
    }
}

/// One account's windows from one reading.
public struct UsageLimits: Equatable, Sendable, Identifiable {
    public enum Source: Equatable, Sendable {
        /// Cached by Claude Code in the profile's `.claude.json` when it checks the account.
        case claudeCode
        /// Copied by the agent into its session log with each reply.
        case sessionLog
    }

    public var agent: AgentKind
    /// Stable per account: Claude's account id, or the Codex home.
    public var account: String
    /// What to call the account when there are several: its email, or the folder it lives in.
    public var label: String?
    public var windows: [UsageLimitWindow]
    public var observedAt: Date
    public var source: Source
    public var id: String { "\(agent.rawValue):\(account)" }

    public init(agent: AgentKind, account: String, label: String? = nil, windows: [UsageLimitWindow], observedAt: Date,
                source: Source) {
        self.agent = agent
        self.account = account
        self.label = label
        self.windows = windows
        self.observedAt = observedAt
        self.source = source
    }

    /// Windows as they stand at `now`: one that renewed since the reading has nothing spent yet.
    public func current(at now: Date) -> [UsageLimitWindow] {
        windows.map { window in
            guard let resets = window.resetsAt, resets <= now else { return window }
            return UsageLimitWindow(id: window.id, kind: window.kind, minutes: window.minutes, scope: window.scope,
                                    usedPercent: 0, resetsAt: nil)
        }
    }

    /// The same reading with renewed windows emptied, so a renewal shows as a change.
    public func asOf(_ now: Date) -> UsageLimits {
        var copy = self
        copy.windows = current(at: now)
        return copy
    }

    /// The window that stops work first: the most spent, and on a tie the one renewing last.
    public func binding(at now: Date) -> UsageLimitWindow? {
        current(at: now).max(by: UsageLimits.tighter)
    }

    /// What a card has room for (vorssaint's choice): the session, and whichever longer window binds first.
    public func shown(at now: Date) -> [UsageLimitWindow] {
        let all = current(at: now)
        let session = all.first { $0.kind == .session }
        let longer = all.filter { $0.kind != .session }.max(by: UsageLimits.tighter)
        return [session, longer].compactMap { $0 }
    }

    /// Across accounts: the window closest to running out, and whose it is. Claude wins a tie.
    public static func tightest(_ limits: [UsageLimits], at now: Date) -> (limits: UsageLimits, window: UsageLimitWindow)? {
        limits.compactMap { limits in limits.binding(at: now).map { (limits, $0) } }
            .max { lhs, rhs in
                lhs.1.usedPercent != rhs.1.usedPercent ? lhs.1.usedPercent < rhs.1.usedPercent
                    : lhs.0.agent.rawValue > rhs.0.agent.rawValue
            }
    }

    public static func tighter(_ lhs: UsageLimitWindow, _ rhs: UsageLimitWindow) -> Bool {
        lhs.usedPercent != rhs.usedPercent ? lhs.usedPercent < rhs.usedPercent
            : (lhs.resetsAt ?? .distantPast) < (rhs.resetsAt ?? .distantPast)
    }
}

public extension UsageLimitWindow {
    /// Share of the window's time already gone, 0...1: where an even pace would have spent it. Nil without
    /// a length or a reset time.
    func elapsed(at now: Date) -> Double? {
        guard let minutes, minutes > 0, let resetsAt, resetsAt > now else { return nil }
        let length = TimeInterval(minutes) * 60
        return min(1, max(0, 1 - resetsAt.timeIntervalSince(now) / length))
    }
}

/// Claude's plan limits as Claude Code caches them per profile, in `.claude.json`
/// (`cachedUsageUtilization`), each time it checks the account. Read in place; nothing is sent, and only
/// the windows below, the account id and its email are kept. Windows this reader does not know are left out.
public enum ClaudeCodeLimits {
    private static let windows: [(key: String, kind: UsageLimitWindow.Kind, minutes: Int, scope: String?)] = [
        ("five_hour", .session, 300, nil), ("seven_day", .weekly, 10_080, nil),
        ("seven_day_opus", .weekly, 10_080, "Opus"), ("seven_day_sonnet", .weekly, 10_080, "Sonnet")]

    public static func limits(profile data: Data) -> UsageLimits? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cached = json["cachedUsageUtilization"] as? [String: Any],
              let utilization = cached["utilization"] as? [String: Any],
              let fetched = (cached["fetchedAtMs"] as? NSNumber)?.doubleValue, fetched.isFinite, fetched > 0
        else { return nil }
        let oauth = json["oauthAccount"] as? [String: Any]
        guard let account = cached["accountUuid"] as? String ?? oauth?["accountUuid"] as? String, !account.isEmpty
        else { return nil }
        var result: [UsageLimitWindow] = []
        for window in windows {
            guard let entry = utilization[window.key] as? [String: Any],
                  let used = entry["utilization"] as? NSNumber, CFGetTypeID(used) != CFBooleanGetTypeID(),
                  used.doubleValue.isFinite
            else { continue }
            let resets = (entry["resets_at"] as? String).flatMap(UsageTimestamp.parse)
            result.append(UsageLimitWindow(id: "claude.\(window.key)", kind: window.kind, minutes: window.minutes,
                                           scope: window.scope, usedPercent: used.doubleValue, resetsAt: resets))
        }
        guard !result.isEmpty else { return nil }
        // The email names the account only when the profile's sign-in is the one the cache belongs to.
        let email = (oauth?["accountUuid"] as? String) == account ? oauth?["emailAddress"] as? String : nil
        return UsageLimits(agent: .claude, account: account, label: email, windows: result,
                           observedAt: Date(timeIntervalSince1970: fetched / 1_000), source: .claudeCode)
    }
}

/// Reads every Claude profile's cached limits, again only when a file changed, one reading per account
/// (the newest, when two profiles share an account). Not thread-safe: the owner confines it to one queue.
public final class ClaudeCodeLimitsReader {
    private let files: () -> [URL]
    private var cache: [String: (modified: Date?, limits: UsageLimits?)] = [:]

    public init(files: @escaping () -> [URL]) { self.files = files }

    public func read() -> [UsageLimits] {
        var accounts: [String: UsageLimits] = [:]
        for url in files() {
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            let limits: UsageLimits?
            if let known = cache[url.path], known.modified == modified {
                limits = known.limits
            } else {
                limits = modified == nil ? nil : (try? Data(contentsOf: url, options: .mappedIfSafe)).flatMap(ClaudeCodeLimits.limits)
                cache[url.path] = (modified, limits)
            }
            guard let limits else { continue }
            if let known = accounts[limits.account], known.observedAt >= limits.observedAt {
                if known.label == nil, let label = limits.label { accounts[limits.account]?.label = label }
                continue
            }
            var newest = limits
            if newest.label == nil { newest.label = accounts[limits.account]?.label }
            accounts[limits.account] = newest
        }
        return accounts.values.sorted { ($0.label ?? $0.account) < ($1.label ?? $1.account) }
    }
}
