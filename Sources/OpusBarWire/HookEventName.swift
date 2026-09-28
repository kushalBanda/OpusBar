/// Claude Code hook events OpusBar subscribes to. Anything else decodes as `.unknown`.
public enum HookEventName: Equatable, Hashable, Sendable {
    case sessionStart
    case userPromptSubmit
    case preToolUse
    case postToolUse
    case postToolUseFailure
    case permissionRequest
    case notification
    case subagentStart
    case subagentStop
    case stop
    case stopFailure
    case sessionEnd
    case unknown(String)

    /// The 12 events written into settings.json, in install order.
    public static let subscribed: [HookEventName] = [
        .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .postToolUseFailure,
        .permissionRequest, .notification, .subagentStart, .subagentStop, .stop, .stopFailure, .sessionEnd,
    ]

    public init(rawValue: String) {
        self = Self.subscribed.first { $0.rawValue == rawValue } ?? .unknown(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .sessionStart: "SessionStart"
        case .userPromptSubmit: "UserPromptSubmit"
        case .preToolUse: "PreToolUse"
        case .postToolUse: "PostToolUse"
        case .postToolUseFailure: "PostToolUseFailure"
        case .permissionRequest: "PermissionRequest"
        case .notification: "Notification"
        case .subagentStart: "SubagentStart"
        case .subagentStop: "SubagentStop"
        case .stop: "Stop"
        case .stopFailure: "StopFailure"
        case .sessionEnd: "SessionEnd"
        case .unknown(let name): name
        }
    }
}

extension HookEventName: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
