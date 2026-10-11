import Foundation
import OpusBarWire

/// How one Claude profile or Codex home is signed in, so an account billed per use reads as that instead of
/// a plan whose limits never arrive.
public struct AccountSignIn: Equatable, Sendable, Identifiable {
    public var agent: AgentKind
    /// The profile or home folder, canonical.
    public var root: String
    /// Its email, or the folder's name.
    public var label: String?
    public var method: SignInMethod
    public var id: String { "\(agent.rawValue):\(root)" }

    public init(agent: AgentKind, root: String, label: String?, method: SignInMethod) {
        self.agent = agent
        self.root = root
        self.label = label
        self.method = method
    }

    /// What a profile's latest session reported from its environment (`SessionStore.signInByAccount`) beats
    /// the profile's files: it is what that process actually used.
    public static func merging(_ accounts: [AccountSignIn], remembered: [String: SignInMethod]) -> [AccountSignIn] {
        var result = accounts
        for (key, method) in remembered.sorted(by: { $0.key < $1.key }) {
            if let index = result.firstIndex(where: { $0.id == key }) {
                result[index].method = method
                continue
            }
            guard let colon = key.firstIndex(of: ":"), let agent = AgentKind(rawValue: String(key[..<colon])) else { continue }
            let root = String(key[key.index(after: colon)...])
            result.append(AccountSignIn(agent: agent, root: root, label: AccountFolder.name(root), method: method))
        }
        return result
    }

    /// The profile or home folder's name: what tells apart two Claude profiles signed in with one email.
    public var folder: String { AccountFolder.name(root) }

    /// Claude: `<root>/projects/<folder>/<id>.jsonl`. Codex: `<home>/sessions/…/rollout-….jsonl` (or
    /// `archived_sessions`).
    static func root(ofTranscript path: String, agent: AgentKind) -> String? {
        switch agent {
        case .claude:
            return PermissionModeReader.configRoot(ofTranscript: path)?.path
        case .codex:
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard let index = parts.lastIndex(where: { $0 == "sessions" || $0 == "archived_sessions" }), index > 0 else { return nil }
            return parts[..<index].joined(separator: "/")
        }
    }
}

public enum ClaudeSignIn {
    /// Where an admin's settings for every profile live.
    public static let managedSettings = URL(filePath: "/Library/Application Support/ClaudeCode/managed-settings.json")

    /// Managed settings, then the profile's `settings.json` (each one's `env` block and `apiKeyHelper`, as
    /// Claude Code applies them), then a key a Console login saved, then the active Anthropic profile
    /// (`anthropicProfile`, its `authentication.type`), then the claude.ai or Console sign-in in `.claude.json`.
    /// Nil when none says.
    public static func method(settings: Data?, account: Data?, managed: Data? = nil, anthropicProfile: String? = nil) -> SignInMethod? {
        for file in [managed, settings].compactMap({ $0 }) {
            if let method = settingsMethod(file, account: account) { return method }
        }
        let accountJSON = account.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        if let key = accountJSON?["primaryApiKey"] as? String, !key.isEmpty { return .apiKey }
        // A federation profile outranks the claude.ai sign-in; a `user_oauth` one (a Console sign-in without
        // a key) only stands in for a missing one.
        let oauth = accountJSON?["oauthAccount"] as? [String: Any]
        if anthropicProfile == "oidc_federation" || (anthropicProfile == "user_oauth" && oauth == nil) { return .apiKey }
        guard let oauth else { return nil }
        // claude.ai organizations are `claude_pro`, `claude_max`, `claude_team`, `claude_enterprise`; a Console
        // organization is anything else.
        if let type = oauth["organizationType"] as? String, !type.isEmpty, !type.hasPrefix("claude_") { return .apiKey }
        return .subscription
    }

    static func settingsMethod(_ data: Data, account: Data?) -> SignInMethod? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let env = json["env"] as? [String: Any] {
            let strings = env.compactMapValues { $0 as? String }
            if let method = SignInMethod.claude(environment: strings, declined: { key in
                account.map { ClaudeKeyResponses.isDeclined(key: key, account: $0) } ?? false
            }) { return method }
        }
        if let helper = json["apiKeyHelper"] as? String, !helper.trimmingCharacters(in: .whitespaces).isEmpty { return .apiKey }
        return nil
    }

    /// The active Anthropic profile's `authentication.type` (`user_oauth`, `oidc_federation`), shared by
    /// every Claude profile: `$ANTHROPIC_CONFIG_DIR` or `~/.config/anthropic`, profile from `active_config`
    /// or `default`. Only that field is read.
    public static func anthropicProfileType(environment: [String: String]) -> String? {
        let home = ClaudeConfigPaths.homeDirectory(environment: environment)
        let dir = environment["ANTHROPIC_CONFIG_DIR"].flatMap { $0.hasPrefix("/") ? URL(filePath: $0, directoryHint: .isDirectory) : nil }
            ?? home.appending(path: ".config/anthropic", directoryHint: .isDirectory)
        let active = (try? String(contentsOf: dir.appending(path: "active_config"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = active.flatMap { $0.isEmpty || $0.contains("/") ? nil : $0 } ?? "default"
        guard let data = try? Data(contentsOf: dir.appending(path: "configs/\(name).json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = (json["authentication"] as? [String: Any])?["type"] as? String, !type.isEmpty else { return nil }
        return type
    }

    /// Settings and account files per profile, read again only when one changed. Not thread-safe.
    public final class Reader {
        private var cache: [String: (stamp: [Date?], profile: String?, method: SignInMethod?)] = [:]

        public init() {}

        /// Profiles with a known method; `emails` names them (`ClaudeCodeLimitsReader.emails`).
        public func read(_ profiles: [ClaudeAccountFiles], emails: [String: String],
                         environment: [String: String] = ProcessInfo.processInfo.environment) -> [AccountSignIn] {
            let anthropicProfile = ClaudeSignIn.anthropicProfileType(environment: environment)
            return profiles.compactMap { profile in
                let root = UsageLogReader.canonical(profile.root.path)
                let settings = profile.root.appending(path: "settings.json")
                let files = [settings, ClaudeSignIn.managedSettings] + profile.files
                let stamp = files.map { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date }
                let method: SignInMethod?
                if let known = cache[root], known.stamp == stamp, known.profile == anthropicProfile {
                    method = known.method
                } else {
                    let account = profile.files.lazy.compactMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }.first
                    method = ClaudeSignIn.method(settings: try? Data(contentsOf: settings), account: account,
                                                 managed: try? Data(contentsOf: ClaudeSignIn.managedSettings),
                                                 anthropicProfile: anthropicProfile)
                    cache[root] = (stamp, anthropicProfile, method)
                }
                return method.map { AccountSignIn(agent: .claude, root: root, label: emails[root] ?? AccountFolder.name(root), method: $0) }
            }
        }
    }
}

public enum CodexSignIn {
    /// Only `auth_mode` is kept; older files without one fall back to which credential is present.
    public static func method(authFile data: Data) -> SignInMethod? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let mode = json["auth_mode"] as? String, !mode.isEmpty { return SignInMethod.codex(authMode: mode) }
        if json["tokens"] is [String: Any] { return .subscription }
        if let key = json["OPENAI_API_KEY"] as? String, !key.isEmpty { return .apiKey }
        return nil
    }

    /// The ChatGPT email from the sign-in's ID token claims, decoded here; nothing is verified or sent.
    public static func email(authFile data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = (json["tokens"] as? [String: Any])?["id_token"] as? String else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let decoded = Data(base64Encoded: payload),
              let claims = (try? JSONSerialization.jsonObject(with: decoded)) as? [String: Any],
              let email = claims["email"] as? String, !email.isEmpty else { return nil }
        return email
    }

    /// A model provider other than OpenAI's own bills elsewhere, whatever the sign-in.
    public static func provider(named name: String) -> SignInMethod? {
        let name = name.lowercased()
        if name.isEmpty || name == "openai" { return nil }
        return name.contains("bedrock") ? .bedrock : .gateway
    }

    /// `model_provider` at the top of `config.toml`, before any table.
    public static func provider(config text: String) -> SignInMethod? {
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { break }
            guard line.hasPrefix("model_provider"), let equals = line.firstIndex(of: "=") else { continue }
            guard line[..<equals].trimmingCharacters(in: .whitespaces) == "model_provider" else { continue }
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#") { value = value[..<hash].trimmingCharacters(in: .whitespaces) }
            return provider(named: value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        }
        return nil
    }

    /// Each home's provider (its newest session's, from `providers`, else `config.toml`'s), else its
    /// `auth.json`. A home that keeps its sign-in in the Keychain has no file: only a provider tells then.
    public static func read(_ homes: [CodexHome], providers: [String: String] = [:]) -> [AccountSignIn] {
        homes.compactMap { home in
            let root = UsageLogReader.canonical(home.root.path)
            let auth = try? Data(contentsOf: home.root.appending(path: "auth.json"))
            let config = (try? Data(contentsOf: home.root.appending(path: "config.toml"))).flatMap { String(data: $0, encoding: .utf8) }
            let used = providers[root].map { provider(named: $0) } ?? config.flatMap(provider(config:))
            guard let method = used ?? auth.flatMap(method(authFile:)) else { return nil }
            return AccountSignIn(agent: .codex, root: root, label: auth.flatMap(email(authFile:)) ?? AccountFolder.name(root),
                                 method: method)
        }
    }

    /// Codex limits named by their home's email, when the sign-in has one.
    public static func labeled(_ limits: [UsageLimits], by signIns: [AccountSignIn]) -> [UsageLimits] {
        limits.map { limits in
            guard limits.agent == .codex,
                  let label = signIns.first(where: { $0.agent == .codex && $0.root == UsageLogReader.canonical(limits.account) })?.label
            else { return limits }
            var named = limits
            named.label = label
            return named
        }
    }
}
