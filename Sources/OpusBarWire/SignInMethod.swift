import Foundation

/// How an agent pays for its replies: a plan with limits, or billed per use. Only plans have limits to show.
public enum SignInMethod: String, Codable, Equatable, Sendable, CaseIterable {
    /// Claude Pro, Max, Team or Enterprise; ChatGPT Plus, Pro, Business or Enterprise.
    case subscription
    /// Claude Console or OpenAI API billing: an API key, a key helper, or a Console sign-in.
    case apiKey
    /// An LLM gateway or proxy (Claude's `ANTHROPIC_AUTH_TOKEN`), or a Codex model provider other than OpenAI.
    case gateway
    case bedrock
    case vertex
    case foundry

    public var hasPlanLimits: Bool { self == .subscription }

    public var label: String {
        switch self {
        case .subscription: "Subscription"
        case .apiKey: "API billing"
        case .gateway: "Custom endpoint"
        case .bedrock: "Amazon Bedrock"
        case .vertex: "Google Vertex AI"
        case .foundry: "Microsoft Foundry"
        }
    }

    /// For a row with little room: "Bedrock", not "Amazon Bedrock".
    public var shortLabel: String {
        switch self {
        case .bedrock: "Bedrock"
        case .vertex: "Vertex AI"
        case .foundry: "Foundry"
        default: label
        }
    }

    /// The variables Claude Code reads, in its own order of precedence. Only whether each is set is looked at;
    /// no value leaves the hook. Nil when none is set: the profile's files decide then.
    /// `declined` says whether the user turned down this `ANTHROPIC_API_KEY` at Claude's prompt.
    public static func claude(environment: [String: String], declined: (String) -> Bool) -> SignInMethod? {
        if isOn(environment["CLAUDE_CODE_USE_BEDROCK"]) { return .bedrock }
        if isOn(environment["CLAUDE_CODE_USE_VERTEX"]) { return .vertex }
        if isOn(environment["CLAUDE_CODE_USE_FOUNDRY"]) { return .foundry }
        if isSet(environment["ANTHROPIC_AUTH_TOKEN"]) { return .gateway }
        if let key = environment["ANTHROPIC_API_KEY"], isSet(key), !declined(key) { return .apiKey }
        if isSet(environment["CLAUDE_CODE_OAUTH_TOKEN"]) { return .subscription }
        // A named Anthropic profile, or Workload Identity Federation: a Console organization's credentials,
        // ranked above the claude.ai sign-in.
        if isSet(environment["ANTHROPIC_PROFILE"]) { return .apiKey }
        if isSet(environment["ANTHROPIC_FEDERATION_RULE_ID"]), isSet(environment["ANTHROPIC_ORGANIZATION_ID"]) { return .apiKey }
        return nil
    }

    /// `CODEX_API_KEY`, which `codex exec` uses over the stored sign-in. Nil otherwise: the home's files decide.
    public static func codex(environment: [String: String]) -> SignInMethod? {
        isSet(environment["CODEX_API_KEY"]) ? .apiKey : nil
    }

    /// Codex's `auth.json` `auth_mode`. Programmatic modes (agent identity, personal access token) say
    /// nothing about billing and give nil.
    public static func codex(authMode: String) -> SignInMethod? {
        switch authMode {
        case "chatgpt", "chatgptAuthTokens": .subscription
        case "apikey": .apiKey
        case "headers": .gateway
        case "bedrockApiKey", "bedrockAccessKeys": .bedrock
        default: nil
        }
    }

    static func isSet(_ value: String?) -> Bool {
        !(value ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// `1`, `true`, `yes`; Claude treats `0` and `false` as off.
    static func isOn(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else { return false }
        return !["0", "false", "no", "off"].contains(value)
    }
}

/// Claude Code remembers the answer to "use this API key?" in the profile's `.claude.json`
/// (`customApiKeyResponses`), by the key's last 20 characters.
public enum ClaudeKeyResponses {
    public static let suffixLength = 20

    /// `.claude.json` inside `CLAUDE_CONFIG_DIR`, else `~/.claude.json`.
    public static func accountFile(environment: [String: String]) -> URL? {
        if let dir = environment["CLAUDE_CONFIG_DIR"], dir.hasPrefix("/") {
            return URL(filePath: dir, directoryHint: .isDirectory).appending(path: ".claude.json")
        }
        guard let home = environment["HOME"], !home.isEmpty else { return nil }
        return URL(filePath: home, directoryHint: .isDirectory).appending(path: ".claude.json")
    }

    public static func isDeclined(key: String, accountFile: URL?) -> Bool {
        guard let accountFile, let data = try? Data(contentsOf: accountFile, options: .mappedIfSafe) else { return false }
        return isDeclined(key: key, account: data)
    }

    public static func isDeclined(key: String, account data: Data) -> Bool {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let responses = json["customApiKeyResponses"] as? [String: Any],
              let rejected = responses["rejected"] as? [String] else { return false }
        return rejected.contains(String(key.trimmingCharacters(in: .whitespaces).suffix(suffixLength)))
    }
}
