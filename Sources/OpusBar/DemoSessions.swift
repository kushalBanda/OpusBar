#if DEBUG
import Foundation
import OpusBarCore
import OpusBarWire

/// `--demo` fills the menu with sample sessions instead of real ones, for the README and website screenshots.
/// No socket, no discovery, and nothing is saved.
enum DemoSessions {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("--demo") }

    private struct Sample {
        let id, project: String
        var branch: String?
        let agent: AgentKind
        let signIn: SignInMethod
        var mode: String?
        let ago: TimeInterval
        let events: [(HookEventName, String?)]
    }

    private static let samples: [Sample] = [
        Sample(id: "d1", project: "payments-api", branch: "refunds", agent: .claude, signIn: .subscription, ago: 13,
               events: [(.userPromptSubmit, nil), (.permissionRequest, "Bash")]),
        Sample(id: "d2", project: "web-app", branch: "main", agent: .claude, signIn: .bedrock, mode: "acceptEdits",
               ago: 53, events: [(.userPromptSubmit, nil), (.preToolUse, "Edit")]),
        Sample(id: "d3", project: "infra", branch: "cdn-cache", agent: .codex, signIn: .apiKey, ago: 53,
               events: [(.userPromptSubmit, nil), (.preToolUse, "shell")]),
        Sample(id: "d4", project: "ml-pipeline", branch: "evals", agent: .codex, signIn: .subscription, ago: 61,
               events: [(.userPromptSubmit, nil)]),
        Sample(id: "d5", project: "design-system", agent: .claude, signIn: .vertex, mode: "plan", ago: 25,
               events: [(.userPromptSubmit, nil), (.stop, nil)]),
        Sample(id: "d6", project: "search-service", branch: "rerank", agent: .claude, signIn: .foundry, ago: 140,
               events: [(.userPromptSubmit, nil), (.stop, nil)]),
    ]

    static func branch(cwd: String) -> String? {
        samples.first { "/demo/\($0.project)" == cwd }?.branch
    }

    /// Plays each sample's events into the store, dated `ago` seconds back through `setClock`.
    @MainActor
    static func play(into store: SessionStore, setClock: (Date?) -> Void) {
        for sample in samples {
            let at = Date().addingTimeInterval(-sample.ago)
            setClock(at)
            for (event, tool) in sample.events {
                store.apply(WireEvent(ts: Int64(at.timeIntervalSince1970 * 1000), agent: sample.agent, signIn: sample.signIn,
                                      e: SlimEvent(sessionId: sample.id, event: event, cwd: "/demo/\(sample.project)",
                                                   permissionMode: sample.mode, toolName: tool)))
            }
        }
        setClock(nil)
    }

    /// Two Claude plans, a Bedrock profile and a Codex plan, with 90 days of replies.
    @MainActor
    static func fill(_ usage: UsageModel) {
        let now = Date()
        let accounts: [(AgentKind, String, String, SignInMethod, String, Double)] = [
            (.claude, "/demo/.claude", "work", .subscription, "claude-opus-4-7", 1.0),
            (.claude, "/demo/.claude-personal", "personal", .subscription, "claude-sonnet-4-6", 0.45),
            (.claude, "/demo/.claude-bedrock", "bedrock", .bedrock, "claude-sonnet-4-6", 0.2),
            (.codex, "/demo/.codex", "codex", .subscription, "gpt-5.5", 0.3),
        ]
        let projects = ["payments-api", "web-app", "infra", "ml-pipeline", "design-system"]
        var seed: UInt64 = 7
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        var records: [UsageRecord] = []
        for hour in 0..<(90 * 24) {
            let date = now.addingTimeInterval(-Double(hour) * 3_600 - 600)
            let ramp = 0.3 + 0.7 * (1 - Double(hour) / 2_160)
            for (agent, root, _, _, model, weight) in accounts where random() < 0.35 * weight * ramp {
                let scale = random() > 0.92 ? 3.0 : 1.0
                var record = UsageRecord(agent: agent, date: date, model: model, project: projects[Int(random() * 5)],
                                         session: "demo-\(Int(random() * 40))", tokens: UsageTokens(input: Int(4_000 * scale), cacheWrite: Int(60_000 * scale),
                                                                              cacheRead: Int(900_000 * scale * random()), output: Int(9_000 * scale)))
                record.account = root
                record.cost = (agent == .claude ? 1.6 : 0.7) * scale * (0.5 + random())
                records.append(record)
            }
        }
        let names = Dictionary(uniqueKeysWithValues: accounts.map { ($0.1, $0.2) })
        var summaries: [UsageRange: UsageSummary] = [:]
        var agentSummaries: [AgentKind: [UsageRange: UsageSummary]] = [:]
        for range in UsageRange.allCases {
            summaries[range] = UsageSummary.make(records: records, range: range, now: now, names: names)
            for agent in AgentKind.allCases {
                agentSummaries[agent, default: [:]][range] = UsageSummary.make(records: records, range: range, now: now,
                                                                              names: names, agent: agent)
            }
        }
        func window(_ kind: UsageLimitWindow.Kind, _ minutes: Int, used: Double, resets: TimeInterval) -> UsageLimitWindow {
            UsageLimitWindow(id: "\(minutes)", kind: kind, minutes: minutes, usedPercent: used, resetsAt: now.addingTimeInterval(resets))
        }
        let limits = [
            UsageLimits(agent: .claude, account: "work", label: "work",
                        windows: [window(.session, 300, used: 25, resets: 8_940), window(.weekly, 10_080, used: 31, resets: 356_400)],
                        observedAt: now, source: .statusLine),
            UsageLimits(agent: .claude, account: "personal", label: "personal",
                        windows: [window(.session, 300, used: 32, resets: 10_740), window(.weekly, 10_080, used: 60, resets: 176_400)],
                        observedAt: now, source: .statusLine),
            UsageLimits(agent: .codex, account: "/demo/.codex",
                        windows: [window(.session, 300, used: 12, resets: 6_000), window(.weekly, 10_080, used: 40, resets: 300_000)],
                        observedAt: now, source: .sessionLog),
        ]
        let signIns = accounts.map { AccountSignIn(agent: $0.0, root: $0.1, label: $0.2, method: $0.3) }
        usage.show(summaries: summaries, agentSummaries: agentSummaries, limits: limits, signIns: signIns)
    }
}
#endif
