import OpusBarCore
import OpusBarWire
import XCTest

final class AccountSignInTests: XCTestCase {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testSettingsEnvBeatsTheSignIn() {
        let settings = json(#"{"env":{"CLAUDE_CODE_USE_BEDROCK":"1"}}"#)
        let account = json(#"{"oauthAccount":{"accountUuid":"a","organizationType":"claude_max"}}"#)
        XCTAssertEqual(ClaudeSignIn.method(settings: settings, account: account), .bedrock)
    }

    func testApiKeyHelperIsPerUse() {
        XCTAssertEqual(ClaudeSignIn.method(settings: json(#"{"apiKeyHelper":"~/bin/key"}"#), account: nil), .apiKey)
    }

    func testClaudeAiAndConsoleSignIns() {
        XCTAssertEqual(ClaudeSignIn.method(settings: nil, account: json(#"{"oauthAccount":{"organizationType":"claude_pro"}}"#)),
                       .subscription)
        XCTAssertEqual(ClaudeSignIn.method(settings: nil, account: json(#"{"oauthAccount":{"accountUuid":"a"}}"#)), .subscription)
        XCTAssertEqual(ClaudeSignIn.method(settings: nil, account: json(#"{"oauthAccount":{"organizationType":"api"}}"#)), .apiKey)
        XCTAssertNil(ClaudeSignIn.method(settings: nil, account: json("{}")), "never signed in")
    }

    func testDeclinedKeyInSettingsFallsBackToTheSignIn() {
        let settings = json(#"{"env":{"ANTHROPIC_API_KEY":"sk-ant-ABCDEFGHIJKLMNOPQRST"}}"#)
        let account = json(#"{"oauthAccount":{"organizationType":"claude_max"},"customApiKeyResponses":{"rejected":["ABCDEFGHIJKLMNOPQRST"]}}"#)
        XCTAssertEqual(ClaudeSignIn.method(settings: settings, account: account), .subscription)
    }

    func testCodexAuthFile() {
        XCTAssertEqual(CodexSignIn.method(authFile: json(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk"}"#)), .apiKey)
        XCTAssertEqual(CodexSignIn.method(authFile: json(#"{"OPENAI_API_KEY":null,"tokens":{"access_token":"x"}}"#)), .subscription)
        XCTAssertEqual(CodexSignIn.method(authFile: json(#"{"OPENAI_API_KEY":"sk"}"#)), .apiKey)
        XCTAssertNil(CodexSignIn.method(authFile: json("{}")))
    }

    func testManagedSettingsWinOverTheUsers() {
        let managed = json(#"{"env":{"CLAUDE_CODE_USE_VERTEX":"1"}}"#)
        let settings = json(#"{"apiKeyHelper":"~/bin/key"}"#)
        XCTAssertEqual(ClaudeSignIn.method(settings: settings, account: nil, managed: managed), .vertex)
        XCTAssertEqual(ClaudeSignIn.method(settings: settings, account: nil, managed: json("{}")), .apiKey,
                       "managed settings that say nothing leave it to the user's")
    }

    func testCodexEmailFromTheIdToken() {
        let claims = Data(#"{"email":"me@x.com","https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}"#.utf8)
            .base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let auth = json(#"{"auth_mode":"chatgpt","tokens":{"id_token":"h.\#(claims).s"}}"#)
        XCTAssertEqual(CodexSignIn.email(authFile: auth), "me@x.com")
        XCTAssertNil(CodexSignIn.email(authFile: json(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk"}"#)))
    }

    func testCodexProviderOutranksTheSignIn() {
        XCTAssertEqual(CodexSignIn.provider(config: "model = \"x\"\nmodel_provider = \"ollama\" # local\n"), .gateway)
        XCTAssertEqual(CodexSignIn.provider(config: "model_provider='amazon-bedrock'"), .bedrock)
        XCTAssertNil(CodexSignIn.provider(config: "model_provider = \"openai\""))
        XCTAssertNil(CodexSignIn.provider(config: "[profiles.local]\nmodel_provider = \"ollama\""), "only the top level")
        XCTAssertNil(CodexSignIn.provider(config: "model_providers_extra = 1"))
    }

    func testSavedConsoleKeyOverridesTheSubscription() {
        let account = json(#"{"primaryApiKey":"sk-ant-x","oauthAccount":{"organizationType":"claude_max"}}"#)
        XCTAssertEqual(ClaudeSignIn.method(settings: nil, account: account), .apiKey)
    }

    func testAnthropicProfiles() {
        let claudeAi = json(#"{"oauthAccount":{"organizationType":"claude_pro"}}"#)
        XCTAssertEqual(ClaudeSignIn.method(settings: nil, account: claudeAi, anthropicProfile: "oidc_federation"), .apiKey,
                       "federation outranks /login")
        XCTAssertEqual(ClaudeSignIn.method(settings: nil, account: claudeAi, anthropicProfile: "user_oauth"), .subscription,
                       "a user_oauth profile ranks below a working /login")
        XCTAssertEqual(ClaudeSignIn.method(settings: nil, account: json("{}"), anthropicProfile: "user_oauth"), .apiKey)
    }

    func testAnthropicProfileTypeFollowsActiveConfig() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "anthropic-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appending(path: "configs"), withIntermediateDirectories: true)
        try json(#"{"version":"1.0","authentication":{"type":"user_oauth"}}"#).write(to: dir.appending(path: "configs/default.json"))
        try json(#"{"authentication":{"type":"oidc_federation"}}"#).write(to: dir.appending(path: "configs/ci.json"))
        let env = ["ANTHROPIC_CONFIG_DIR": dir.path]
        XCTAssertEqual(ClaudeSignIn.anthropicProfileType(environment: env), "user_oauth")
        try json("ci\n").write(to: dir.appending(path: "active_config"))
        XCTAssertEqual(ClaudeSignIn.anthropicProfileType(environment: env), "oidc_federation")
        XCTAssertNil(ClaudeSignIn.anthropicProfileType(environment: ["ANTHROPIC_CONFIG_DIR": dir.path + "-none"]))
    }

    func testCodexSessionProviderBeatsConfigAndSignIn() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "codexhome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try json(#"{"auth_mode":"chatgpt","tokens":{}}"#).write(to: home.appending(path: "auth.json"))
        try json(#"model_provider = "ollama""#).write(to: home.appending(path: "config.toml"))
        let codex = CodexHome(root: home, origin: .userAdded)
        let resolved = realpath(home.path, nil)
        defer { free(resolved) }
        let root = resolved.map { String(cString: $0) } ?? home.path
        XCTAssertEqual(CodexSignIn.read([codex]).map(\.method), [.gateway], "config.toml without logs")
        XCTAssertEqual(CodexSignIn.read([codex], providers: [root: "openai"]).map(\.method), [.subscription],
                       "the newest session used OpenAI: the sign-in decides")
        XCTAssertEqual(CodexSignIn.read([codex], providers: [root: "amazon-bedrock"]).map(\.method), [.bedrock])
    }

    func testCodexLogKeepsTheSessionsProvider() {
        var state = CodexUsageParser.State()
        let line = Data(#"{"timestamp":"2026-10-11T10:00:00.000Z","type":"session_meta","payload":{"id":"s1","cwd":"/tmp/a","model_provider":"ollama"}}"#.utf8)
        _ = CodexUsageParser.parse(line, state: &state)
        XCTAssertEqual(state.provider, "ollama")
        XCTAssertNotNil(state.providerAt)
    }

    func testRememberedSignInOverridesItsProfile() {
        let profile = AccountSignIn(agent: .claude, root: "/Users/me/.claude", label: "me@x.com", method: .subscription)
        let merged = AccountSignIn.merging([profile], remembered: ["claude:/Users/me/.claude": .bedrock])
        XCTAssertEqual(merged.map(\.method), [.bedrock])
        XCTAssertEqual(merged.first?.label, "me@x.com")
        XCTAssertEqual(merged.first?.folder, "claude")
        let added = AccountSignIn.merging([], remembered: ["codex:/Users/me/.codex-work": .apiKey])
        XCTAssertEqual(added.map(\.agent), [.codex])
        XCTAssertEqual(added.first?.label, "codex-work")
    }

    @MainActor
    func testStoreRemembersEachProfilesLatestSignIn() {
        var saved: [String: SignInMethod] = [:]
        let store = SessionStore(isAlive: { _ in true }, branchReader: { _ in nil }, subagentMeta: { _, _ in nil },
                                 saveSignIns: { saved = $0 })
        func send(_ id: String, _ transcript: String, _ signIn: SignInMethod?, agent: AgentKind? = nil, ts: Int64) {
            var e = SlimEvent(sessionId: id, event: .userPromptSubmit)
            e.cwd = "/tmp/p"
            e.transcriptPath = transcript
            store.apply(WireEvent(ts: ts, agent: agent, signIn: signIn, e: e))
        }
        send("a", "/nonexistent/.claude/projects/-tmp-p/a.jsonl", .bedrock, ts: 1)
        send("b", "/nonexistent/.claude-kb/projects/-tmp-p/b.jsonl", nil, ts: 2)
        send("c", "/nonexistent/.codex/sessions/2026/10/11/rollout-c.jsonl", .apiKey, agent: .codex, ts: 3)
        XCTAssertEqual(store.signInByAccount, ["claude:/nonexistent/.claude": .bedrock, "codex:/nonexistent/.codex": .apiKey])
        XCTAssertEqual(saved, store.signInByAccount)
        send("d", "/nonexistent/.claude/projects/-tmp-p/d.jsonl", nil, ts: 4)
        XCTAssertNil(store.signInByAccount["claude:/nonexistent/.claude"], "a plain session hands the profile back to its files")
    }

    func testSessionBillingFallsBackToItsProfile() {
        var session = Session(id: "s", cwd: "/tmp", startedAt: Date())
        session.transcriptPath = "/nonexistent/.claude/projects/-tmp/s.jsonl"
        let profile = AccountSignIn(agent: .claude, root: "/nonexistent/.claude", label: nil, method: .apiKey)
        XCTAssertEqual(AccountSignIn.billing(of: session, accounts: [profile]), .apiKey)
        session.signIn = .bedrock
        XCTAssertEqual(AccountSignIn.billing(of: session, accounts: [profile]), .bedrock, "the session's own environment wins")
        XCTAssertNil(AccountSignIn.billing(of: Session(id: "t", cwd: "/tmp", startedAt: Date()), accounts: [profile]))
    }
}
