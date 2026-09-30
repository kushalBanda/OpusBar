import Darwin
import Foundation

/// Reads one Claude Code transcript line into a billed reply. Only assistant lines with `message.usage`
/// count; usage counters, model, ids, time and folder name are kept, never message content.
public enum ClaudeUsageParser {
    /// `key` identifies the reply across streamed copies and files: message id + request id,
    /// or session + message id when a proxy left out the request id.
    public static func parse(_ line: Data) -> (key: String, record: UsageRecord)? {
        // Structural keys are written without spaces, so a byte match skips most lines without decoding them.
        guard line.contains(assistantMarker), line.contains(usageMarker),
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, !model.isEmpty, !model.hasPrefix("<"),
              let date = (json["timestamp"] as? String).flatMap(UsageTimestamp.parse)
        else { return nil }
        let tokens = UsageTokens(
            input: int(usage["input_tokens"]),
            cacheWrite: int(usage["cache_creation_input_tokens"]),
            cacheWrite1h: int((usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"]),
            cacheRead: int(usage["cache_read_input_tokens"]),
            output: int(usage["output_tokens"]))
        guard tokens.total > 0 else { return nil }
        let session = json["sessionId"] as? String ?? ""
        let messageId = message["id"] as? String ?? ""
        let requestId = json["requestId"] as? String ?? ""
        let key = switch (messageId.isEmpty, requestId.isEmpty) {
        case (false, false): "claude:\(messageId):\(requestId)"
        case (false, true): "claude:\(session):\(messageId)"
        default: "claude:\(session):\(date.timeIntervalSince1970)"
        }
        let record = UsageRecord(agent: .claude, date: date, model: model,
                                 project: (json["cwd"] as? String).map(projectFolder) ?? "",
                                 session: session, tokens: tokens,
                                 fast: usage["speed"] as? String == "fast",
                                 usOnly: usage["inference_geo"] as? String == "us",
                                 webSearches: int((usage["server_tool_use"] as? [String: Any])?["web_search_requests"]))
        return (key, record)
    }

    /// The folder a reply was made in, as the store's project resolver expects it. A worktree kept inside
    /// the repository counts as that repository.
    public static func projectFolder(_ cwd: String) -> String {
        var path = cwd
        if let range = path.range(of: "/.claude/worktrees/") { path = String(path[..<range.lowerBound]) }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static let assistantMarker = Data(#""type":"assistant""#.utf8)
    private static let usageMarker = Data(#""usage""#.utf8)

    /// A non-negative whole count; anything else (missing, negative, damaged) is 0.
    static func int(_ value: Any?) -> Int {
        guard let number = value as? NSNumber else { return 0 }
        let double = number.doubleValue
        guard double.isFinite, double > 0 else { return 0 }
        return Int(min(double, 1e12))
    }
}

extension Data {
    /// Byte search without decoding (memmem): the first filter over every log line.
    func contains(_ needle: Data) -> Bool {
        withUnsafeBytes { haystack in
            needle.withUnsafeBytes { needle in
                guard let base = haystack.baseAddress, let target = needle.baseAddress, haystack.count >= needle.count
                else { return false }
                return memmem(base, haystack.count, target, needle.count) != nil
            }
        }
    }
}
