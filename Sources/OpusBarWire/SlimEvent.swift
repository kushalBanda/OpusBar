import Foundation

/// The only parts of a Claude Code hook payload that leave the hook process.
/// Prompt text, tool input/output and assistant messages are dropped here.
public struct SlimEvent: Codable, Equatable, Sendable {
    public var sessionId: String
    public var event: HookEventName
    public var cwd: String?
    public var transcriptPath: String?
    public var permissionMode: String?
    public var toolName: String?
    public var notificationType: String?
    /// SessionStart: startup, resume, clear, compact.
    public var source: String?
    /// SessionEnd: clear, logout, prompt_input_exit, other.
    public var reason: String?
    public var agentId: String?
    public var agentType: String?

    public init(
        sessionId: String,
        event: HookEventName,
        cwd: String? = nil,
        transcriptPath: String? = nil,
        permissionMode: String? = nil,
        toolName: String? = nil,
        notificationType: String? = nil,
        source: String? = nil,
        reason: String? = nil,
        agentId: String? = nil,
        agentType: String? = nil
    ) {
        self.sessionId = sessionId
        self.event = event
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.permissionMode = permissionMode
        self.toolName = toolName
        self.notificationType = notificationType
        self.source = source
        self.reason = reason
        self.agentId = agentId
        self.agentType = agentType
    }

    public enum SlimError: Error, Equatable {
        case notAnObject
        case missingField(String)
    }

    /// Parses Claude's hook JSON and keeps only whitelisted fields.
    public static func slim(hookJSON: Data) throws -> SlimEvent {
        guard let object = try JSONSerialization.jsonObject(with: hookJSON) as? [String: Any] else {
            throw SlimError.notAnObject
        }
        func string(_ key: String) -> String? { object[key] as? String }
        guard let sessionId = string("session_id"), !sessionId.isEmpty else {
            throw SlimError.missingField("session_id")
        }
        guard let eventName = string("hook_event_name") else {
            throw SlimError.missingField("hook_event_name")
        }
        return SlimEvent(
            sessionId: sessionId,
            event: HookEventName(rawValue: eventName),
            cwd: string("cwd"),
            transcriptPath: string("transcript_path"),
            permissionMode: string("permission_mode"),
            toolName: string("tool_name"),
            notificationType: string("notification_type"),
            source: string("source"),
            reason: string("reason"),
            agentId: string("agent_id"),
            agentType: string("agent_type")
        )
    }
}
