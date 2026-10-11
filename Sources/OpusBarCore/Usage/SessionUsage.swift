import Foundation

/// What one agent session has used so far: every reply logged under its id, subagents included, and the
/// same split per subagent. Prices are API list prices, as everywhere in Usage.
public struct SessionUsage: Equatable, Sendable {
    public var total = UsageTotals()
    /// By subagent id (`agentId`); the main thread isn't listed.
    public var bySubagent: [String: UsageTotals] = [:]

    public init() {}

    /// Sessions with a reply since `activeSince`, each summed over all its replies held. Older sessions
    /// can't be on a card, and leaving them out keeps the result small.
    public static func make(records: [UsageRecord], activeSince: Date) -> [String: SessionUsage] {
        let active = Set(records.lazy.filter { $0.date >= activeSince && !$0.session.isEmpty }.map(\.session))
        var result: [String: SessionUsage] = [:]
        for record in records where active.contains(record.session) {
            result[record.session, default: SessionUsage()].total.add(record)
            if !record.agentId.isEmpty {
                result[record.session, default: SessionUsage()].bySubagent[record.agentId, default: UsageTotals()].add(record)
            }
        }
        return result
    }
}
