import Foundation

/// One subagent a session started (Claude's Agent tool), live from hooks: SubagentStart adds it, tool events
/// that carry its `agent_id` move it, SubagentStop removes it. Background subagents outlive the parent's
/// turn, so a parent's Stop leaves them alone.
public struct Subagent: Identifiable, Equatable, Sendable {
    public let id: String
    /// `Explore`, `general-purpose`, a custom agent's name.
    public var type: String
    /// The task the parent gave it, from the subagent's `meta.json`; nil until Claude has written it.
    public var description: String?
    /// The tool it is running; nil while it thinks.
    public var tool: String?
    public var startedAt: Date
    public var lastEventAt: Date

    /// A subagent silent this long lost its SubagentStop (crash, killed terminal) and is dropped.
    public static let staleAfter: TimeInterval = 30 * 60

    public init(id: String, type: String, description: String? = nil, tool: String? = nil, startedAt: Date, lastEventAt: Date? = nil) {
        self.id = id
        self.type = type
        self.description = description
        self.tool = tool
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt ?? startedAt
    }

    /// "Explore", "General purpose": agent types are ids, shown as words.
    public var typeLabel: String {
        guard !type.isEmpty else { return "Subagent" }
        let words = type.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// `<root>/projects/<folder>/<session>.jsonl` → `<root>/projects/<folder>/<session>/subagents/agent-<id>.meta.json`.
    public static func metaURL(transcriptPath: String, agentId: String) -> URL {
        let transcript = URL(filePath: transcriptPath)
        return transcript.deletingPathExtension()
            .appending(path: "subagents").appending(path: "agent-\(agentId).meta.json")
    }

    /// The task description Claude saved for the subagent. Only `description` and `agentType` are read.
    public static func readMeta(transcriptPath: String, agentId: String) -> (type: String?, description: String?)? {
        guard let data = try? Data(contentsOf: metaURL(transcriptPath: transcriptPath, agentId: agentId)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let description = (json["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return (json["agentType"] as? String, description)
    }
}
