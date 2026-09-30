import Foundation
import OpusBarWire

/// Token counts of one reply. `input` excludes cache traffic; `cacheWrite1h` is the part of
/// `cacheWrite` kept for an hour (billed higher than 5-minute writes).
public struct UsageTokens: Equatable, Sendable {
    public var input = 0
    public var cacheWrite = 0
    public var cacheWrite1h = 0
    public var cacheRead = 0
    public var output = 0

    public init(input: Int = 0, cacheWrite: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheWrite = cacheWrite
        self.cacheWrite1h = min(cacheWrite1h, cacheWrite)
        self.cacheRead = cacheRead
        self.output = output
    }

    public var total: Int { input + cacheWrite + cacheRead + output }

    /// Claude writes a streamed reply once per content block; earlier copies carry partial counts,
    /// so the largest reading of each field is the final one.
    public func merged(with other: UsageTokens) -> UsageTokens {
        UsageTokens(input: max(input, other.input), cacheWrite: max(cacheWrite, other.cacheWrite),
                    cacheWrite1h: max(cacheWrite1h, other.cacheWrite1h), cacheRead: max(cacheRead, other.cacheRead),
                    output: max(output, other.output))
    }

    public static func += (lhs: inout UsageTokens, rhs: UsageTokens) {
        lhs.input += rhs.input
        lhs.cacheWrite += rhs.cacheWrite
        lhs.cacheWrite1h += rhs.cacheWrite1h
        lhs.cacheRead += rhs.cacheRead
        lhs.output += rhs.output
    }
}

/// One billed reply, read from an agent's local log. Never holds prompt or reply text.
public struct UsageRecord: Equatable, Sendable {
    public var agent: AgentKind
    public var date: Date
    public var model: String
    /// The folder the agent ran in as parsed; the store turns it into the project name (git repository
    /// folder, else the folder's own name).
    public var project: String
    public var session: String
    public var tokens: UsageTokens
    /// Claude fast mode (`usage.speed == "fast"`), Codex fast/priority tier.
    public var fast: Bool
    /// Claude US-only inference (`usage.inference_geo == "us"`).
    public var usOnly: Bool
    public var webSearches: Int
    /// What the reply would cost at API list prices, in US dollars; nil when the model has no known price.
    /// Set by the ledger, which holds the price list.
    public var cost: Double?

    public init(agent: AgentKind, date: Date, model: String, project: String, session: String, tokens: UsageTokens,
                fast: Bool = false, usOnly: Bool = false, webSearches: Int = 0, cost: Double? = nil) {
        self.agent = agent
        self.date = date
        self.model = model
        self.project = project
        self.session = session
        self.tokens = tokens
        self.fast = fast
        self.usOnly = usOnly
        self.webSearches = webSearches
        self.cost = cost
    }

    /// Copies of one reply: largest token counts, and any copy's extras.
    func merged(with other: UsageRecord) -> UsageRecord {
        var merged = self
        merged.tokens = tokens.merged(with: other.tokens)
        merged.fast = fast || other.fast
        merged.usOnly = usOnly || other.usOnly
        merged.webSearches = max(webSearches, other.webSearches)
        return merged
    }
}

/// Sums over a range of replies.
public struct UsageTotals: Equatable, Sendable {
    public var tokens = UsageTokens()
    /// API value of the priced replies.
    public var cost = 0.0
    public var replies = 0
    /// Replies from a model without a known price, left out of `cost`.
    public var unpriced = 0

    public init() {}

    public mutating func add(_ record: UsageRecord) {
        tokens += record.tokens
        replies += 1
        if let cost = record.cost { self.cost += cost } else { unpriced += 1 }
    }
}

/// Replies by key: copies of one reply (streamed blocks, the same reply in two files) collapse into one.
/// Each reply is priced here, with the list the ledger was made with.
public struct UsageLedger: Sendable {
    public private(set) var records: [UsageRecord] = []
    private var index: [String: Int] = [:]
    let prices: UsagePriceList

    public init(prices: UsagePriceList) {
        self.prices = prices
    }

    public mutating func add(_ record: UsageRecord, key: String) {
        guard let position = index[key] else {
            var record = record
            record.cost = prices.cost(record)
            index[key] = records.count
            records.append(record)
            return
        }
        var merged = records[position].merged(with: record)
        merged.cost = records[position].cost
        guard merged != records[position] else { return }
        merged.cost = prices.cost(merged)
        records[position] = merged
    }

    /// Keeps memory bounded to the history that can be shown.
    public mutating func drop(before date: Date) {
        guard records.contains(where: { $0.date < date }) else { return }
        var kept: [UsageRecord] = []
        var positions: [Int: Int] = [:]
        for (offset, record) in records.enumerated() where record.date >= date {
            positions[offset] = kept.count
            kept.append(record)
        }
        index = index.compactMapValues { positions[$0] }
        records = kept
    }

    public func totals(since: Date) -> UsageTotals {
        records.reduce(into: UsageTotals()) { totals, record in
            if record.date >= since { totals.add(record) }
        }
    }
}
