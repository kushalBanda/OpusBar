import Foundation
import OpusBarWire

/// The ranges the Usage and Spend pane offers. Only the last 24 hours is free (M4 plan, owner).
public enum UsageRange: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, quarter

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .day: "24 h"
        case .week: "7 d"
        case .month: "30 d"
        case .quarter: "90 d"
        }
    }

    /// Calendar days covered, today included; nil for the rolling 24 hours.
    public var days: Int? {
        switch self {
        case .day: nil
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    /// The one gate for usage ranges: Pro unlocks everything past 24 hours.
    public func isAvailable(isPro: Bool) -> Bool { isPro || self == .day }

    /// 24 h rolls with the clock; the others start at local midnight so their day bars are whole days.
    public func start(now: Date, calendar: Calendar = .current) -> Date {
        guard let days else { return now.addingTimeInterval(-86_400) }
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    }
}

/// One row of a breakdown: an agent, a model or a project.
public struct UsageShare: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// The agent behind the row, when there is exactly one.
    public var agent: AgentKind?
    public var totals: UsageTotals
}

/// One bar of the trend: a local calendar day, or an hour in the 24 h range.
public struct UsageDay: Equatable, Sendable, Identifiable {
    public var start: Date
    public var totals: UsageTotals
    /// The same, per agent, for bars stacked by agent.
    public var byAgent: [AgentKind: UsageTotals] = [:]
    public var id: Date { start }

    public init(start: Date, totals: UsageTotals, byAgent: [AgentKind: UsageTotals] = [:]) {
        self.start = start
        self.totals = totals
        self.byAgent = byAgent
    }

    mutating func add(_ record: UsageRecord) {
        totals.add(record)
        byAgent[record.agent, default: UsageTotals()].add(record)
    }
}

/// Everything the pane shows for one range.
public struct UsageSummary: Equatable, Sendable {
    public var range: UsageRange
    public var since: Date
    public var total: UsageTotals
    public var byAgent: [UsageShare]
    public var byModel: [UsageShare]
    /// Largest eight, then "Other".
    public var byProject: [UsageShare]
    /// Oldest first, ending today; empty for the 24 h range.
    public var days: [UsageDay]
    /// The 24 h range by hour, oldest first, ending with the current hour; empty for the other ranges.
    public var hours: [UsageDay] = []
    /// Bars for this range's trend: hours for 24 h, days otherwise.
    public var trend: [UsageDay] { range == .day ? hours : days }

    public static let projectLimit = 8

    public static func make(records: [UsageRecord], range: UsageRange, now: Date,
                            calendar: Calendar = .current) -> UsageSummary {
        let since = range.start(now: now, calendar: calendar)
        var total = UsageTotals()
        var agents: [AgentKind: UsageTotals] = [:]
        var models: [String: (agent: AgentKind, totals: UsageTotals)] = [:]
        var projects: [String: (agents: Set<AgentKind>, totals: UsageTotals)] = [:]
        var dayIndex: [Date: Int] = [:]
        var days: [UsageDay] = []
        if let count = range.days {
            for offset in 0..<count {
                guard let start = calendar.date(byAdding: .day, value: offset, to: since) else { continue }
                dayIndex[start] = days.count
                days.append(UsageDay(start: start, totals: UsageTotals()))
            }
        }
        // 24 bars ending with the current hour; the first holds what the rolling window keeps of its hour.
        var hours: [UsageDay] = []
        let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        if range == .day {
            hours = (0..<24).reversed().map { UsageDay(start: thisHour.addingTimeInterval(-3_600 * Double($0)), totals: UsageTotals()) }
        }
        for record in records where record.date >= since && record.date <= now {
            total.add(record)
            agents[record.agent, default: UsageTotals()].add(record)
            let model = UsageFormat.modelName(record.model)
            models[model, default: (record.agent, UsageTotals())].totals.add(record)
            let project = record.project.isEmpty ? "Unknown folder" : record.project
            projects[project, default: ([], UsageTotals())].agents.insert(record.agent)
            projects[project]?.totals.add(record)
            if let position = dayIndex[calendar.startOfDay(for: record.date)] { days[position].add(record) }
            if !hours.isEmpty {
                let position = 23 + Int((record.date.timeIntervalSince(thisHour) / 3_600).rounded(.down))
                if hours.indices.contains(position) { hours[position].add(record) }
            }
        }
        let byAgent = agents.map { UsageShare(id: $0.key.rawValue, name: $0.key.displayName, agent: $0.key, totals: $0.value) }
        let byModel = models.map { UsageShare(id: $0.key, name: $0.key, agent: $0.value.agent, totals: $0.value.totals) }
        var byProject = ranked(projects.map {
            UsageShare(id: $0.key, name: $0.key, agent: $0.value.agents.count == 1 ? $0.value.agents.first : nil, totals: $0.value.totals)
        })
        if byProject.count > projectLimit {
            var other = UsageTotals()
            for share in byProject[projectLimit...] { other += share.totals }
            byProject = Array(byProject.prefix(projectLimit))
                + [UsageShare(id: "\u{0}other", name: "Other", agent: nil, totals: other)]
        }
        return UsageSummary(range: range, since: since, total: total, byAgent: ranked(byAgent), byModel: ranked(byModel),
                            byProject: byProject, days: days, hours: hours)
    }

    /// Most API value first; then most tokens (unpriced models), then name, so order is stable.
    static func ranked(_ shares: [UsageShare]) -> [UsageShare] {
        shares.sorted {
            ($0.totals.cost, $0.totals.tokens.total, $1.name) > ($1.totals.cost, $1.totals.tokens.total, $0.name)
        }
    }
}

public extension UsageTokens {
    /// Share of the prompt that came from the cache; nil with no prompt tokens.
    var cacheHitRate: Double? {
        let prompt = input + cacheWrite + cacheRead
        return prompt > 0 ? Double(cacheRead) / Double(prompt) : nil
    }
}

public extension UsageTotals {
    static func += (lhs: inout UsageTotals, rhs: UsageTotals) {
        lhs.tokens += rhs.tokens
        lhs.cost += rhs.cost
        lhs.replies += rhs.replies
        lhs.unpriced += rhs.unpriced
    }
}
