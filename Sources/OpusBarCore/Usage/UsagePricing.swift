import Foundation

/// US dollars per million tokens for one model family.
public struct UsagePrice: Equatable, Sendable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    /// 5-minute cache writes (Claude) or cache writes (OpenAI). Input price when a provider doesn't bill writes separately.
    public var cacheWrite: Double
    /// Claude 1-hour cache writes.
    public var cacheWrite1h: Double
    /// Premium on every token kind for the fast tier; 1 where none is sold.
    public var fast: Double = 1
    public var longContext: LongContext?

    /// Past `above` prompt tokens, input-side rates × `input` and output × `output`.
    public struct LongContext: Equatable, Sendable {
        public var above: Int
        public var input: Double
        public var output: Double
    }
}

/// API list prices, shipped with the app as `usage-prices.json` (ADR 4: never downloaded).
/// A list that breaks any rule is refused as a whole.
public struct UsagePriceList: Equatable, Sendable {
    public struct Model: Equatable, Sendable {
        public var id: String
        public var price: UsagePrice
    }

    public static let schema = 1

    /// Day the list was last checked against the providers' pages, "YYYY-MM-DD".
    public var updated: String
    public var claude: [Model]
    public var openai: [Model]
    /// Claude web search, per search.
    public var webSearch: Double
    /// Claude US-only inference (`inference_geo: "us"`), on every token kind.
    public var usOnlyMultiplier: Double

    public static let empty = UsagePriceList(updated: "", claude: [], openai: [], webSearch: 0, usOnlyMultiplier: 1)

    // MARK: Pricing

    /// The price of the longest listed family that `model` belongs to; nil when none does.
    public func price(for model: String) -> UsagePrice? {
        let id = Self.normalized(model)
        let table = id.hasPrefix("claude-") ? claude : openai
        guard let match = table.filter({ Self.matches(id, family: $0.id) }).max(by: { $0.id.count < $1.id.count })
        else { return nil }
        // An unlisted smaller, larger or specialised sibling is priced very differently: no figure beats a wrong one.
        let rest = id.dropFirst(match.id.count)
        return Self.siblings.contains(where: { rest.contains($0) }) ? nil : match.price
    }

    /// What `record` costs at API list prices; nil when its model has no price.
    public func cost(_ record: UsageRecord) -> Double? {
        guard let price = price(for: record.model) else { return nil }
        let tokens = record.tokens
        var inputRate = record.fast ? price.fast : 1
        if record.usOnly { inputRate *= usOnlyMultiplier }
        var outputRate = inputRate
        let prompt = tokens.input + tokens.cacheWrite + tokens.cacheRead
        if let long = price.longContext, prompt > long.above {
            inputRate *= long.input
            outputRate *= long.output
        }
        let shortWrites = tokens.cacheWrite - tokens.cacheWrite1h
        let inputSide = Double(tokens.input) * price.input + Double(shortWrites) * price.cacheWrite
            + Double(tokens.cacheWrite1h) * price.cacheWrite1h + Double(tokens.cacheRead) * price.cacheRead
        return (inputSide * inputRate + Double(tokens.output) * price.output * outputRate) / 1_000_000
            + Double(record.webSearches) * webSearch
    }

    /// Lowercased, without a route prefix (`anthropic/…`), a Vertex snapshot (`@…`) or a context tag (`[1m]`).
    static func normalized(_ model: String) -> String {
        var id = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = id.lastIndex(of: "/") { id = String(id[id.index(after: slash)...]) }
        if let range = id.range(of: "claude-") { id = String(id[range.lowerBound...]) }
        for marker: Character in ["@", "["] {
            if let index = id.firstIndex(of: marker) { id = String(id[..<index]) }
        }
        return id
    }

    /// Words that make a variant a model of its own.
    static let siblings = ["mini", "nano", "pro", "lite", "research", "search", "audio", "realtime", "cyber", "image"]

    /// A family matches at a word break: "gpt-5.4" is not "gpt-5.4.1", and a number after it names
    /// another version ("claude-opus-5" is not "claude-opus-5-5"); a date after it is the same model.
    static func matches(_ id: String, family: String) -> Bool {
        guard id.hasPrefix(family) else { return false }
        let rest = id.dropFirst(family.count)
        guard let next = rest.first else { return true }
        guard next == "-" || next == "_" || next == ":" else { return false }
        let number = rest.dropFirst().prefix { $0.isNumber }
        return number.isEmpty || number.count >= 6
    }

    // MARK: Decoding

    public static func decode(_ data: Data) -> UsagePriceList? {
        guard data.count <= 256 << 10,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              number(json["schema"], in: 1...1_000) == Double(schema),
              let updated = json["updated"] as? String, isDay(updated),
              let claude = json["claude"] as? [String: Any], let openai = json["openai"] as? [String: Any],
              let claudeModels = models(claude["models"], claude: true),
              let openaiModels = models(openai["models"], claude: false),
              let webSearch = number(claude["webSearch"], in: 0...1),
              let usOnly = number(claude["usOnlyMultiplier"], in: 1...3)
        else { return nil }
        return UsagePriceList(updated: updated, claude: claudeModels, openai: openaiModels,
                              webSearch: webSearch, usOnlyMultiplier: usOnly)
    }

    private static func models(_ value: Any?, claude: Bool) -> [Model]? {
        guard let entries = value as? [[String: Any]], (1...500).contains(entries.count) else { return nil }
        var seen = Set<String>()
        var result: [Model] = []
        for entry in entries {
            guard let id = entry["id"] as? String, isIdentifier(id), seen.insert(id).inserted,
                  id.hasPrefix("claude-") == claude,
                  let input = number(entry["input"], in: 0...1_000),
                  let output = number(entry["output"], in: 0...1_000),
                  let cacheRead = number(entry["cacheRead"], in: 0...1_000)
            else { return nil }
            // Left out: writes bill at input price, 1 h writes like 5 min writes, no fast premium.
            let cacheWrite = entry["cacheWrite"] == nil ? input : number(entry["cacheWrite"], in: 0...1_000)
            let cacheWrite1h = entry["cacheWrite1h"] == nil ? cacheWrite : number(entry["cacheWrite1h"], in: 0...1_000)
            let fast = entry["fast"] == nil ? 1 : number(entry["fast"], in: 1...10)
            guard let cacheWrite, let cacheWrite1h, let fast else { return nil }
            var long: UsagePrice.LongContext?
            if let value = entry["longContext"] {
                guard let object = value as? [String: Any],
                      let above = number(object["above"], in: 1_000...10_000_000),
                      let longInput = number(object["input"], in: 1...10),
                      let longOutput = number(object["output"], in: 1...10)
                else { return nil }
                long = UsagePrice.LongContext(above: Int(above), input: longInput, output: longOutput)
            }
            result.append(Model(id: id, price: UsagePrice(input: input, output: output, cacheRead: cacheRead,
                                                          cacheWrite: cacheWrite, cacheWrite1h: cacheWrite1h,
                                                          fast: fast, longContext: long)))
        }
        return result
    }

    /// Lowercase letters, digits, dots, dashes and underscores: the shape of every model id the agents log.
    private static func isIdentifier(_ text: String) -> Bool {
        (1...64).contains(text.count) && text.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-" || $0 == "_"
        }
    }

    /// A finite number inside `range`; JSON true/false is not one.
    private static func number(_ value: Any?, in range: ClosedRange<Double>) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite && range.contains(double) ? double : nil
    }

    private static func isDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-")
        return parts.count == 3 && parts.map(\.count) == [4, 2, 2] && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}
