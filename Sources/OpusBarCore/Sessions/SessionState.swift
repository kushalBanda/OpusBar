public enum SessionState: String, Sendable, CaseIterable {
    case idle
    case thinking
    case working
    case needsAttention
    case done
    case error

    /// Higher is more urgent. Drives sort order and the menu bar summary.
    public var urgency: Int {
        switch self {
        case .error: 5
        case .needsAttention: 4
        case .working, .thinking: 3
        case .done: 2
        case .idle: 1
        }
    }

    /// Breaks the working/thinking tie: working is louder.
    var loudness: Int {
        urgency * 2 + (self == .working ? 1 : 0)
    }

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .working: "Working"
        case .needsAttention: "Needs you"
        case .done: "Done"
        case .error: "Error"
        }
    }
}
