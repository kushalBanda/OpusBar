import Foundation
@testable import OpusBarCore
import OpusBarWire
import XCTest

final class SubagentAndSessionUsageTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testStaleSubagentsArePruned() {
        var session = Session(id: "s", cwd: "/x", startedAt: t0)
        session.subagents = [Subagent(id: "old", type: "Explore", startedAt: t0),
                             Subagent(id: "new", type: "Explore", startedAt: t0, lastEventAt: t0.addingTimeInterval(Subagent.staleAfter))]
        let pruned = SessionPruner.prune(SessionsState(byId: ["s": session]), now: t0.addingTimeInterval(Subagent.staleAfter + 1),
                                         finishedTTL: 600, isAlive: { _ in true })
        XCTAssertEqual(pruned.byId["s"]?.subagents.map(\.id), ["new"])
    }

    func testMetaSitsBesideTheTranscript() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "meta-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let transcript = folder.appending(path: "projects/-x/abc.jsonl").path
        let meta = Subagent.metaURL(transcriptPath: transcript, agentId: "a1")
        XCTAssertEqual(meta.path, folder.appending(path: "projects/-x/abc/subagents/agent-a1.meta.json").path)
        XCTAssertNil(Subagent.readMeta(transcriptPath: transcript, agentId: "a1"))
        try FileManager.default.createDirectory(at: meta.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"agentType":"Explore","description":"Find the auth code","toolUseId":"t"}"#.utf8).write(to: meta)
        let read = try XCTUnwrap(Subagent.readMeta(transcriptPath: transcript, agentId: "a1"))
        XCTAssertEqual(read.type, "Explore")
        XCTAssertEqual(read.description, "Find the auth code")
    }

    @MainActor
    func testStoreFillsTheDescriptionOnceWritten() {
        var written = false
        let store = SessionStore(subagentMeta: { _, _ in written ? ("Explore", "Find the auth code") : nil })
        func send(_ name: HookEventName, ts: Int64, tool: String? = nil) {
            store.apply(WireEvent(ts: ts, pid: 7, e: SlimEvent(sessionId: "s", event: name, cwd: "/x", transcriptPath: "/r/projects/-x/s.jsonl",
                                                             toolName: tool, agentId: "a1", agentType: "Explore")))
        }
        send(.subagentStart, ts: 1)
        XCTAssertNil(store.state.byId["s"]?.subagents.first?.description)
        written = true
        send(.preToolUse, ts: 2, tool: "Grep")
        XCTAssertEqual(store.state.byId["s"]?.subagents.first?.description, "Find the auth code")
    }

    func testSessionUsageSumsSessionsActiveRecently() {
        func record(_ session: String, _ agent: String = "", day: Double, input: Int, cost: Double?) -> UsageRecord {
            var r = UsageRecord(agent: .claude, date: t0.addingTimeInterval(day * 86_400), model: "m", project: "p", session: session,
                                tokens: UsageTokens(input: input, cacheWrite: 10, cacheRead: 100, output: 5), cost: cost)
            r.agentId = agent
            return r
        }
        let records = [record("live", day: -5, input: 1, cost: 1), record("live", day: 0, input: 2, cost: 2),
                       record("live", "sub1", day: 0, input: 4, cost: 0.5), record("old", day: -5, input: 9, cost: 9),
                       record("live", day: 0, input: 8, cost: nil)]
        let usage = SessionUsage.make(records: records, activeSince: t0.addingTimeInterval(-86_400))
        XCTAssertEqual(Set(usage.keys), ["live"])
        let live = try! XCTUnwrap(usage["live"])
        XCTAssertEqual(live.total.tokens.input, 15)
        XCTAssertEqual(live.total.tokens.cacheRead, 400)
        XCTAssertEqual(live.total.cost, 3.5, accuracy: 1e-9)
        XCTAssertEqual(live.total.unpriced, 1)
        XCTAssertEqual(live.bySubagent["sub1"]?.tokens.input, 4)
    }

    func testClaudeParserKeepsTheSubagentId() throws {
        let line = #"{"type":"assistant","agentId":"a1","sessionId":"s","timestamp":"2026-10-11T08:00:00.000Z","requestId":"r","message":{"id":"m","model":"claude-opus-5-5","usage":{"input_tokens":3,"output_tokens":2}}}"#
        XCTAssertEqual(try XCTUnwrap(ClaudeUsageParser.parse(Data(line.utf8))).record.agentId, "a1")
    }
}
