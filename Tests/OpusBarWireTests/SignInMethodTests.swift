import OpusBarWire
import XCTest

final class SignInMethodTests: XCTestCase {
    private func claude(_ environment: [String: String], declined: Bool = false) -> SignInMethod? {
        SignInMethod.claude(environment: environment) { _ in declined }
    }

    func testClaudeFollowsClaudesPrecedence() {
        XCTAssertNil(claude([:]), "nothing set: the profile's files decide")
        XCTAssertEqual(claude(["CLAUDE_CODE_USE_BEDROCK": "1", "ANTHROPIC_API_KEY": "sk"]), .bedrock)
        XCTAssertEqual(claude(["CLAUDE_CODE_USE_VERTEX": "true"]), .vertex)
        XCTAssertEqual(claude(["CLAUDE_CODE_USE_FOUNDRY": "1"]), .foundry)
        XCTAssertEqual(claude(["ANTHROPIC_AUTH_TOKEN": "t", "ANTHROPIC_API_KEY": "sk"]), .gateway)
        XCTAssertEqual(claude(["ANTHROPIC_API_KEY": "sk", "CLAUDE_CODE_OAUTH_TOKEN": "o"]), .apiKey)
        XCTAssertEqual(claude(["CLAUDE_CODE_OAUTH_TOKEN": "o"]), .subscription)
    }

    func testOffValuesAndBlanksDontCount() {
        XCTAssertNil(claude(["CLAUDE_CODE_USE_BEDROCK": "0"]))
        XCTAssertNil(claude(["CLAUDE_CODE_USE_VERTEX": "false"]))
        XCTAssertNil(claude(["ANTHROPIC_API_KEY": "  "]))
    }

    func testDeclinedKeyFallsThrough() {
        XCTAssertNil(claude(["ANTHROPIC_API_KEY": "sk"], declined: true))
        XCTAssertEqual(claude(["ANTHROPIC_API_KEY": "sk", "CLAUDE_CODE_OAUTH_TOKEN": "o"], declined: true), .subscription)
    }

    func testDeclinedMatchesTheKeysLastTwentyCharacters() {
        let key = "sk-ant-api03-" + String(repeating: "x", count: 10) + "ABCDEFGHIJKLMNOPQRST"
        let rejected = Data(#"{"customApiKeyResponses":{"approved":[],"rejected":["ABCDEFGHIJKLMNOPQRST"]}}"#.utf8)
        let approved = Data(#"{"customApiKeyResponses":{"approved":["ABCDEFGHIJKLMNOPQRST"],"rejected":[]}}"#.utf8)
        XCTAssertTrue(ClaudeKeyResponses.isDeclined(key: key, account: rejected))
        XCTAssertFalse(ClaudeKeyResponses.isDeclined(key: key, account: approved))
        XCTAssertFalse(ClaudeKeyResponses.isDeclined(key: key, account: Data("{}".utf8)))
    }

    func testAccountFileFollowsConfigDir() {
        XCTAssertEqual(ClaudeKeyResponses.accountFile(environment: ["HOME": "/Users/me"])?.path, "/Users/me/.claude.json")
        XCTAssertEqual(ClaudeKeyResponses.accountFile(environment: ["HOME": "/Users/me", "CLAUDE_CONFIG_DIR": "/Users/me/.claude-work"])?.path,
                       "/Users/me/.claude-work/.claude.json")
    }

    func testCodexAuthModes() {
        XCTAssertEqual(SignInMethod.codex(authMode: "chatgpt"), .subscription)
        XCTAssertEqual(SignInMethod.codex(authMode: "chatgptAuthTokens"), .subscription)
        XCTAssertEqual(SignInMethod.codex(authMode: "apikey"), .apiKey)
        XCTAssertEqual(SignInMethod.codex(authMode: "bedrockAccessKeys"), .bedrock)
        XCTAssertNil(SignInMethod.codex(authMode: "personalAccessToken"))
    }

    func testWireCarriesSignInAndToleratesUnknown() throws {
        let event = WireEvent(ts: 1, signIn: .apiKey, e: SlimEvent(sessionId: "s", event: .stop))
        XCTAssertEqual(try WireEvent.decode(line: event.encodedLine()).signIn, .apiKey)
        let newer = Data(#"{"v":1,"ts":1,"signIn":"somethingNew","e":{"sessionId":"s","event":"Stop"}}"#.utf8)
        XCTAssertNil(try WireEvent.decode(line: newer).signIn)
    }

    func testCodexEnvironment() {
        XCTAssertEqual(SignInMethod.codex(environment: ["CODEX_API_KEY": "sk"]), .apiKey)
        XCTAssertNil(SignInMethod.codex(environment: ["OPENAI_API_KEY": "sk"]), "Codex signs in through auth.json, not this")
    }

    func testAnthropicProfileAndFederationRankBelowTheOAuthToken() {
        XCTAssertEqual(claude(["ANTHROPIC_PROFILE": "work"]), .apiKey)
        XCTAssertEqual(claude(["ANTHROPIC_FEDERATION_RULE_ID": "fdrl_1", "ANTHROPIC_ORGANIZATION_ID": "o"]), .apiKey)
        XCTAssertNil(claude(["ANTHROPIC_FEDERATION_RULE_ID": "fdrl_1"]), "both are needed")
        XCTAssertEqual(claude(["ANTHROPIC_PROFILE": "work", "CLAUDE_CODE_OAUTH_TOKEN": "o"]), .subscription)
    }
}
