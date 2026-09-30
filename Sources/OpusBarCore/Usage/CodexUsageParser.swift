import Darwin
import Foundation

/// Reads Codex rollout lines (`sessions/**/rollout-*.jsonl`) into billed replies. Usage lines carry no model
/// or folder, so the file's earlier lines (`session_meta`, `turn_context`) are remembered in `State`.
/// Only counters, ids, model, tier, time and folder name are kept, never message content.
public enum CodexUsageParser {
    public struct State: Equatable, Sendable {
        public var session = ""
        public var project = ""
        public var model = ""
        /// Fast tier (named "priority" before mid 2026) bills at a premium.
        public var fast = false
        /// The latest plan limits the file copied from the server, main allowance only.
        public var limits: UsageLimits?
        /// Newer rollouts write one `token_usage_record` per reply; older ones only running totals,
        /// used until a record appears.
        var sawRecords = false
        var lastTotal: RawUsage?

        public init() {}
    }

    /// Codex's own counts: `input` includes cached and cache-write tokens.
    struct RawUsage: Equatable, Sendable {
        var input = 0, cached = 0, written = 0, output = 0

        init(_ json: [String: Any]) {
            input = ClaudeUsageParser.int(json["input_tokens"])
            cached = ClaudeUsageParser.int(json["cached_input_tokens"])
            written = ClaudeUsageParser.int(json["cache_write_input_tokens"])
            output = ClaudeUsageParser.int(json["output_tokens"])
        }

        init(input: Int, cached: Int, written: Int, output: Int) {
            (self.input, self.cached, self.written, self.output) = (input, cached, written, output)
        }

        var total: Int { input + output }

        /// Disjoint counts; reasoning tokens are already inside `output`.
        var tokens: UsageTokens {
            let cached = min(input, cached)
            let written = min(input - cached, written)
            return UsageTokens(input: input - cached - written, cacheWrite: written, cacheRead: cached, output: output)
        }

        func minus(_ other: RawUsage) -> RawUsage {
            RawUsage(input: max(0, input - other.input), cached: max(0, cached - other.cached),
                     written: max(0, written - other.written), output: max(0, output - other.output))
        }
    }

    /// Line types that can matter. A rollout line writes its own type first and an event's payload opens
    /// with the event type, so both are found within the first bytes, without decoding tool output or
    /// compacted history that can run to megabytes per line.
    private static let lineTypes: Set<String> = ["session_meta", "turn_context", "token_usage_record", "event_msg"]
    private static let eventTypes: Set<String> = ["token_count", "thread_settings_applied"]

    public static func parse(_ line: Data, state: inout State) -> (key: String, record: UsageRecord)? {
        guard let kind = firstType(line), lineTypes.contains(kind.name) else { return nil }
        if kind.name == "event_msg" {
            guard let event = firstType(line, from: kind.end), eventTypes.contains(event.name) else { return nil }
        }
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = json["payload"] as? [String: Any]
        else { return nil }
        let date = (json["timestamp"] as? String).flatMap(UsageTimestamp.parse)
        switch json["type"] as? String {
        case "session_meta":
            if let id = payload["id"] as? String, !id.isEmpty { state.session = id }
            if let cwd = payload["cwd"] as? String, !cwd.isEmpty { state.project = ClaudeUsageParser.projectFolder(cwd) }
        case "turn_context":
            if let model = payload["model"] as? String, !model.isEmpty { state.model = model }
            if let cwd = payload["cwd"] as? String, !cwd.isEmpty { state.project = ClaudeUsageParser.projectFolder(cwd) }
            state.fast = isFast(payload["service_tier"] as? String)
        case "token_usage_record":
            guard let usage = payload["usage"] as? [String: Any], let date else { return nil }
            state.sawRecords = true
            if state.session.isEmpty, let session = payload["session_id"] as? String { state.session = session }
            let response = payload["response_id"] as? String ?? ""
            let key = response.isEmpty ? "codex:\(state.session):\(date.timeIntervalSince1970)" : "codex:\(response)"
            return reply(RawUsage(usage).tokens, key: key, date: date, state: state)
        case "event_msg":
            if payload["type"] as? String == "thread_settings_applied" {
                let settings = payload["thread_settings"] as? [String: Any]
                if let tier = settings?["service_tier"] as? String { state.fast = isFast(tier) }
                return nil
            }
            if let date, let rateLimits = payload["rate_limits"] as? [String: Any], let reading = limits(rateLimits, observed: date),
               reading.observedAt >= (state.limits?.observedAt ?? .distantPast) {
                state.limits = reading
            }
            // Running totals repeat when only the limits changed; a reply is what the total grew by.
            guard !state.sawRecords, let date, let info = payload["info"] as? [String: Any],
                  let totalJSON = info["total_token_usage"] as? [String: Any]
            else { return nil }
            let total = RawUsage(totalJSON)
            let previous = state.lastTotal
            state.lastTotal = total
            guard total != previous, total.total > (previous?.total ?? 0) else { return nil }
            let delta = (info["last_token_usage"] as? [String: Any]).map(RawUsage.init) ?? total.minus(previous ?? RawUsage([:]))
            return reply(delta.tokens, key: "codex:\(state.session):total:\(total.total)", date: date, state: state)
        default:
            break
        }
        return nil
    }

    /// Codex logs a reading per allowance: the main one under "codex" (unnamed in older logs), and one per
    /// model that has its own. Only the main one is kept. Windows are told apart by length, never by slot:
    /// an account can report only its weekly window, in either slot.
    static func limits(_ json: [String: Any], observed: Date) -> UsageLimits? {
        let id = (json["limit_id"] as? String ?? "").lowercased()
        guard id.isEmpty || id == "codex" else { return nil }
        var windows: [UsageLimitWindow] = []
        for slot in ["primary", "secondary"] {
            guard let window = json[slot] as? [String: Any], let used = (window["used_percent"] as? NSNumber)?.doubleValue,
                  used.isFinite
            else { continue }
            let minutes = (window["window_minutes"] as? NSNumber)?.intValue
            var resets = (window["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            if resets == nil, let delay = (window["resets_in_seconds"] as? NSNumber)?.doubleValue, delay.isFinite {
                resets = observed.addingTimeInterval(max(0, delay))
            }
            windows.append(UsageLimitWindow(id: "codex.\(minutes.map(String.init) ?? slot)", kind: UsageLimitWindow.kind(minutes: minutes),
                                            minutes: minutes, usedPercent: used, resetsAt: resets))
        }
        guard !windows.isEmpty else { return nil }
        return UsageLimits(agent: .codex, account: "codex", windows: windows.sorted { ($0.minutes ?? .max) < ($1.minutes ?? .max) },
                           observedAt: observed, source: .sessionLog)
    }

    static func isFast(_ tier: String?) -> Bool {
        ["fast", "priority"].contains(tier?.lowercased() ?? "")
    }

    private static func reply(_ tokens: UsageTokens, key: String, date: Date, state: State) -> (key: String, record: UsageRecord)? {
        guard tokens.total > 0 else { return nil }
        return (key, UsageRecord(agent: .codex, date: date, model: state.model, project: state.project,
                                 session: state.session, tokens: tokens, fast: state.fast))
    }

    /// The first `"type":"…"` value at or after `start`, looked for only in the first bytes.
    static func firstType(_ line: Data, from start: Int = 0) -> (name: String, end: Int)? {
        let key = Data(#""type":""#.utf8)
        return line.withUnsafeBytes { bytes -> (String, Int)? in
            guard let base = bytes.baseAddress, start < bytes.count else { return nil }
            let window = min(bytes.count - start, 256)
            let found: UnsafeMutableRawPointer? = key.withUnsafeBytes { needle in
                memmem(base + start, window, needle.baseAddress, needle.count)
            }
            guard let found else { return nil }
            let value = base.distance(to: found) + key.count
            let limit = min(bytes.count, value + 64)
            guard value < limit, let quote = memchr(base + value, 0x22, limit - value) else { return nil }
            let end = base.distance(to: UnsafeRawPointer(quote))
            return (String(decoding: UnsafeRawBufferPointer(rebasing: bytes[value..<end]), as: UTF8.self), end + 1)
        }
    }
}
