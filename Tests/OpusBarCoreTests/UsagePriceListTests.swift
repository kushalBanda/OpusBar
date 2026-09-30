@testable import OpusBarCore
import OpusBarWire
import XCTest

final class UsagePriceListTests: XCTestCase {
    /// The list shipped in the app, read from the source tree.
    static let bundled: UsagePriceList = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/OpusBar/Resources/usage-prices.json")
        return UsagePriceList.decode(try! Data(contentsOf: url))!
    }()

    private var list: UsagePriceList { Self.bundled }

    private func record(_ model: String, _ tokens: UsageTokens, fast: Bool = false, usOnly: Bool = false,
                        webSearches: Int = 0) -> UsageRecord {
        UsageRecord(agent: model.hasPrefix("claude") ? .claude : .codex, date: Date(), model: model, project: "p",
                    session: "s", tokens: tokens, fast: fast, usOnly: usOnly, webSearches: webSearches)
    }

    func testBundledListDecodes() {
        XCTAssertEqual(list.updated, "2026-09-30")
        XCTAssertGreaterThan(list.claude.count, 10)
        XCTAssertGreaterThan(list.openai.count, 10)
    }

    func testFamilyMatchingRules() {
        XCTAssertEqual(list.price(for: "claude-opus-5-5")?.input, 4)
        XCTAssertEqual(list.price(for: "claude-opus-5")?.input, 5, "a later point release is its own row")
        XCTAssertEqual(list.price(for: "claude-haiku-4-5-20251001")?.input, 1, "a date snapshot is the same model")
        XCTAssertEqual(list.price(for: "anthropic/claude-sonnet-5")?.input, 2, "route prefix dropped")
        XCTAssertEqual(list.price(for: "claude-opus-4-5@20251101")?.input, 5, "Vertex @ snapshot dropped")
        XCTAssertEqual(list.price(for: "Claude-Sonnet-4-6[1m]")?.input, 3, "case and context tag ignored")
        XCTAssertNil(list.price(for: "claude-opus-5-7"), "an unlisted later version is not the one before it")
        XCTAssertEqual(list.price(for: "gpt-5.2-codex")?.input, 1.75)
        XCTAssertEqual(list.price(for: "gpt-5.4")?.input, 2.5)
        XCTAssertNil(list.price(for: "gpt-5.4.1"), "gpt-5.4 is not gpt-5.4.1")
        XCTAssertNil(list.price(for: "gpt-6-sol-mini"), "an unlisted smaller sibling gets no price")
        XCTAssertNil(list.price(for: "claude-mystery-9"))
    }

    func testCostCoversEveryTokenKindAndExtras() throws {
        let tokens = UsageTokens(input: 1_000_000, cacheWrite: 2_000_000, cacheWrite1h: 1_000_000, cacheRead: 1_000_000, output: 1_000_000)
        // Opus 5.5: input 4 + 5 min writes 5 + 1 h writes 8 + reads 0.2 + output 20
        XCTAssertEqual(try XCTUnwrap(list.cost(record("claude-opus-5-5", tokens))), 37.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(list.cost(record("claude-opus-5-5", tokens, fast: true))), 74.4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(list.cost(record("claude-opus-5-5", tokens, usOnly: true))), 40.92, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(list.cost(record("claude-opus-5-5", tokens, webSearches: 3))), 37.23, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(list.cost(record("claude-sonnet-4-6", tokens, fast: true))), 28.05,
                       accuracy: 1e-9, "no fast price on Sonnet: billed at standard")
        XCTAssertNil(list.cost(record("claude-mystery-9", tokens)))
    }

    func testOpenAIMissingCacheWriteBillsAsInputAndLongContextPremium() throws {
        let short = UsageTokens(input: 100_000, cacheWrite: 100_000, cacheRead: 0, output: 100_000)
        // gpt-5.4: input 2.5, no cache write price (input), output 15
        XCTAssertEqual(try XCTUnwrap(list.cost(record("gpt-5.4", short))), 0.25 + 0.25 + 1.5, accuracy: 1e-9)
        let long = UsageTokens(input: 300_000, output: 100_000)
        XCTAssertEqual(try XCTUnwrap(list.cost(record("gpt-5.4", long))), 0.75 * 2 + 1.5 * 1.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(list.cost(record("gpt-5.4", long, fast: true))), (0.75 * 2 + 1.5 * 1.5) * 2, accuracy: 1e-9)
    }

    func testBrokenListIsRefusedAsAWhole() {
        func decode(_ text: String) -> UsagePriceList? { UsagePriceList.decode(Data(text.utf8)) }
        let model = #"{ "id": "claude-x-1", "input": 1, "output": 2, "cacheRead": 0.1 }"#
        func doc(schema: Int = 1, claude: String = model, openai: String = #"{ "id": "gpt-x", "input": 1, "output": 2, "cacheRead": 0.1 }"#) -> String {
            #"{"schema":\#(schema),"updated":"2026-09-30","claude":{"webSearch":0.01,"usOnlyMultiplier":1.1,"models":[\#(claude)]},"openai":{"models":[\#(openai)]}}"#
        }
        XCTAssertNotNil(decode(doc()))
        XCTAssertNil(decode(doc(schema: 2)), "a later schema waits for an app that reads it")
        XCTAssertNil(decode(doc(claude: model + "," + model)), "duplicate id")
        XCTAssertNil(decode(doc(claude: #"{ "id": "claude-x-1", "input": -1, "output": 2, "cacheRead": 0.1 }"#)), "negative price")
        XCTAssertNil(decode(doc(claude: #"{ "id": "claude-x-1", "input": true, "output": 2, "cacheRead": 0.1 }"#)), "a boolean is not a price")
        XCTAssertNil(decode(doc(claude: #"{ "id": "gpt-x-1", "input": 1, "output": 2, "cacheRead": 0.1 }"#)), "claude table holds claude ids only")
        XCTAssertNil(decode(doc(openai: #"{ "id": "claude-x-2", "input": 1, "output": 2, "cacheRead": 0.1 }"#)), "and openai none")
        XCTAssertNil(decode("[]"))
    }
}
