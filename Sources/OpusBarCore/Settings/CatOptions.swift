import Foundation

/// The cat's look: one oneko.js sprite sheet each. Only coats whose art rights are checked ship
/// (ADRs 16, 17). Order is the order the Cat pane shows them in.
public enum CatCoat: String, CaseIterable, Sendable {
    // Public domain X11 oneko art, and OpusBar's own recolours of it.
    case classic, black, gray, silver, ghost, tora
    // MIT: catppuccineko, spicetify-oneko.
    case catppuccin, maia, vaporwave
    // MIT: generated from Classic by 0xdhrv/oneko.
    case ginger, sage, siamese
    case strawberryMilk = "strawberry-milk", blueFrost = "blue-frost"
    case lavender, tuxedo, peach, honey, mocha, mint
    case midnightBlue = "midnight-blue"

    public var label: String {
        switch self {
        case .strawberryMilk: "Strawberry Milk"
        case .blueFrost: "Blue Frost"
        case .midnightBlue: "Midnight Blue"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// Resource name of the 256 x 128 sheet, in the bundle's `Coats` folder.
    public var sheetName: String { "oneko-\(rawValue)" }
}

/// Something the cat can do, as frames on the oneko.js sheet ((column, row) in the 8 x 4 grid).
public enum CatPose: String, CaseIterable, Sendable {
    case sit, alert, groom, scratchWall, yawn, nap, run, runToYou

    public var label: String {
        switch self {
        case .sit: "Sit"
        case .alert: "Alert"
        case .groom: "Groom"
        case .scratchWall: "Scratch wall"
        case .yawn: "Yawn"
        case .nap: "Nap"
        case .run: "Run"
        case .runToYou: "Run to you"
        }
    }

    public var frames: [(col: Int, row: Int)] {
        switch self {
        case .sit: [(3, 3)]
        case .alert: [(7, 3)]
        case .groom: [(5, 0), (6, 0), (7, 0), (6, 0)]
        case .scratchWall: [(4, 0), (4, 1)]
        case .yawn: [(3, 2)]
        case .nap: [(2, 0), (2, 1)]
        case .run: [(3, 0), (3, 1)]      // trots in place, facing right
        case .runToYou: [(6, 3), (7, 2)] // runs toward the viewer
        }
    }

    /// Seconds per frame; 0 for a still pose.
    public var interval: TimeInterval {
        switch self {
        case .sit, .alert, .yawn: 0
        case .groom: 0.22
        case .scratchWall: 0.25
        case .nap: 0.7
        case .run, .runToYou: 0.3
        }
    }
}

/// What the cat does for each session state. `nil` state (no sessions) uses the idle pose.
public struct CatPoses: Equatable, Sendable {
    private var chosen: [SessionState: CatPose]

    public init(_ chosen: [SessionState: CatPose] = [:]) {
        // Keep only choices offered for that state.
        self.chosen = chosen.filter { Self.choices(for: $0.key).contains($0.value) }
    }

    public static let defaults = CatPoses()

    /// Defaults first; the order the Cat pane shows them in.
    public static func choices(for state: SessionState) -> [CatPose] {
        switch state {
        case .working: [.run, .scratchWall, .groom]
        case .thinking: [.groom, .scratchWall, .sit]
        case .needsAttention: [.alert, .runToYou]
        case .done: [.nap, .sit, .yawn]
        case .error: [.yawn, .alert]
        case .idle: [.sit, .nap]
        }
    }

    public func pose(for state: SessionState?) -> CatPose {
        let state = state ?? .idle
        return chosen[state] ?? Self.choices(for: state)[0]
    }

    public mutating func set(_ pose: CatPose, for state: SessionState) {
        guard Self.choices(for: state).contains(pose) else { return }
        chosen[state] = pose == Self.choices(for: state)[0] ? nil : pose
    }

    /// Saved form: state raw value to pose raw value, only where it differs from the default.
    public var stored: [String: String] {
        Dictionary(uniqueKeysWithValues: chosen.map { ($0.key.rawValue, $0.value.rawValue) })
    }

    public init(stored: [String: String]) {
        self.init(Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            guard let state = SessionState(rawValue: key), let pose = CatPose(rawValue: value) else { return nil }
            return (state, pose)
        }))
    }
}

/// How big the menu bar cat is. Clamped to the menu bar's own height when drawn.
public enum MenuBarCatSize: String, CaseIterable, Sendable {
    case small, medium, large

    public var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// 16 pt is the 32 px frame 1:1 on Retina; bigger sizes scale it nearest-neighbor.
    public var points: Double {
        switch self {
        case .small: 16
        case .medium: 20
        case .large: 24
        }
    }
}

/// What the menu bar cat looks like while no session is running.
public enum EmptyMenuBarCat: String, CaseIterable, Sendable {
    case dimmed, full, asleep

    public var label: String {
        switch self {
        case .dimmed: "Dimmed"
        case .full: "Awake"
        case .asleep: "Asleep"
        }
    }
}

/// How fast the menu bar cat may animate. Each frame is a menu bar redraw, so even Normal is capped
/// at 4 frames a second (ADR 9).
public enum CatPace: String, CaseIterable, Sendable {
    case calm, normal

    public var label: String {
        switch self {
        case .calm: "Calm"
        case .normal: "Normal"
        }
    }

    public var minFrameInterval: TimeInterval {
        switch self {
        case .calm: 0.5
        case .normal: 0.25
        }
    }
}

/// The menu bar cat's settings together, and the rules that turn them into a drawing.
public struct MenuBarLook: Equatable, Sendable {
    public var size: MenuBarCatSize = .medium
    public var showsBadge = true
    public var empty: EmptyMenuBarCat = .dimmed
    public var pace: CatPace = .normal

    public init(size: MenuBarCatSize = .medium, showsBadge: Bool = true, empty: EmptyMenuBarCat = .dimmed, pace: CatPace = .normal) {
        self.size = size
        self.showsBadge = showsBadge
        self.empty = empty
        self.pace = pace
    }

    /// Seconds per menu bar frame: the pose's own pace, never faster than the chosen cap.
    public func frameInterval(for poseInterval: TimeInterval) -> TimeInterval {
        max(poseInterval, pace.minFrameInterval)
    }

    /// The pose with no sessions running: the idle pose, or a nap when asleep is chosen.
    public func pose(for state: SessionState?, poses: CatPoses) -> CatPose {
        state == nil && empty == .asleep ? .nap : poses.pose(for: state)
    }

    public func alpha(hasSessions: Bool) -> Double {
        !hasSessions && empty == .dimmed ? 0.5 : 1
    }

    /// Points to draw the cat at: the chosen size, but never taller than the menu bar leaves room for.
    public func catPoints(barThickness: Double) -> Double {
        min(size.points, max(16, barThickness - 2))
    }
}
