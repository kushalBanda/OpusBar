import Foundation
import OpusBarWire
import Observation

/// How long done and errored sessions stay in the list.
public enum FinishedRetention: String, CaseIterable, Sendable {
    case fiveMinutes, tenMinutes, oneHour, never

    public var seconds: TimeInterval {
        switch self {
        case .fiveMinutes: 5 * 60
        case .tenMinutes: 10 * 60
        case .oneHour: 60 * 60
        case .never: .infinity
        }
    }

    public var label: String {
        switch self {
        case .fiveMinutes: "5 min"
        case .tenMinutes: "10 min"
        case .oneHour: "1 hour"
        case .never: "Never"
        }
    }
}

/// What a session card is titled with.
public enum SessionNaming: String, CaseIterable, Sendable {
    case folder, folderAndBranch

    public var label: String {
        switch self {
        case .folder: "Folder"
        case .folderAndBranch: "Folder and branch"
        }
    }
}

/// The user's free, local choices. Backed by UserDefaults; each write persists at once.
/// Launch at login is not here: the system owns that state (SMAppService).
@MainActor @Observable
public final class Preferences {
    enum Key {
        static let animateCat = "animateCat"
        static let retention = "finishedRetention"
        static let naming = "sessionNaming"
        static let notifyNeedsYou = "notifyNeedsYou"
        static let notifyError = "notifyError"
        static let notifyDone = "notifyDone"
        static let connectCardDismissed = "connectCardDismissed"
        static let coat = "catCoat"
        static let poses = "catPoses"
        static let barSize = "menuBarCatSize"
        static let barBadge = "menuBarBadge"
        static let barEmpty = "menuBarEmpty"
        static let barPace = "menuBarPace"
        static let notifyLimitReset = "notifyLimitReset"
        static let limitResetMuted = "limitResetMutedAccounts"
        static let notifyLimitWarning = "notifyLimitWarning"
    }

    public var animateCat: Bool { didSet { defaults.set(animateCat, forKey: Key.animateCat) } }
    public var retention: FinishedRetention { didSet { defaults.set(retention.rawValue, forKey: Key.retention) } }
    public var naming: SessionNaming { didSet { defaults.set(naming.rawValue, forKey: Key.naming) } }
    public var notifyNeedsYou: Bool { didSet { defaults.set(notifyNeedsYou, forKey: Key.notifyNeedsYou) } }
    public var notifyError: Bool { didSet { defaults.set(notifyError, forKey: Key.notifyError) } }
    /// Off by default: with many sessions it gets chatty.
    public var notifyDone: Bool { didSet { defaults.set(notifyDone, forKey: Key.notifyDone) } }
    public var connectCardDismissed: Bool { didSet { defaults.set(connectCardDismissed, forKey: Key.connectCardDismissed) } }
    /// A notification when a plan window with some use renews.
    public var notifyLimitReset: Bool { didSet { defaults.set(notifyLimitReset, forKey: Key.notifyLimitReset) } }
    /// A notification when a plan window reaches 80 % and 95 % used.
    public var notifyLimitWarning: Bool { didSet { defaults.set(notifyLimitWarning, forKey: Key.notifyLimitWarning) } }
    /// Accounts (`UsageLimits.id`) whose limit notifications (resets and warnings) stay quiet.
    public var limitResetMuted: Set<String> {
        didSet { defaults.set(limitResetMuted.sorted(), forKey: Key.limitResetMuted) }
    }
    public var coat: CatCoat { didSet { defaults.set(coat.rawValue, forKey: Key.coat) } }
    public var poses: CatPoses { didSet { defaults.set(poses.stored, forKey: Key.poses) } }
    public var menuBar: MenuBarLook {
        didSet {
            defaults.set(menuBar.size.rawValue, forKey: Key.barSize)
            defaults.set(menuBar.showsBadge, forKey: Key.barBadge)
            defaults.set(menuBar.empty.rawValue, forKey: Key.barEmpty)
            defaults.set(menuBar.pace.rawValue, forKey: Key.barPace)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        animateCat = defaults.object(forKey: Key.animateCat) as? Bool ?? true
        retention = defaults.string(forKey: Key.retention).flatMap(FinishedRetention.init) ?? .tenMinutes
        naming = defaults.string(forKey: Key.naming).flatMap(SessionNaming.init) ?? .folder
        notifyNeedsYou = defaults.object(forKey: Key.notifyNeedsYou) as? Bool ?? true
        notifyError = defaults.object(forKey: Key.notifyError) as? Bool ?? true
        notifyDone = defaults.object(forKey: Key.notifyDone) as? Bool ?? false
        connectCardDismissed = defaults.bool(forKey: Key.connectCardDismissed)
        notifyLimitReset = defaults.object(forKey: Key.notifyLimitReset) as? Bool ?? true
        notifyLimitWarning = defaults.object(forKey: Key.notifyLimitWarning) as? Bool ?? true
        limitResetMuted = Set(defaults.stringArray(forKey: Key.limitResetMuted) ?? [])
        coat = defaults.string(forKey: Key.coat).flatMap(CatCoat.init) ?? .classic
        poses = CatPoses(stored: defaults.dictionary(forKey: Key.poses) as? [String: String] ?? [:])
        menuBar = MenuBarLook(
            size: defaults.string(forKey: Key.barSize).flatMap(MenuBarCatSize.init) ?? .medium,
            showsBadge: defaults.object(forKey: Key.barBadge) as? Bool ?? true,
            empty: defaults.string(forKey: Key.barEmpty).flatMap(EmptyMenuBarCat.init) ?? .dimmed,
            pace: defaults.string(forKey: Key.barPace).flatMap(CatPace.init) ?? .normal)
    }

    public var notificationRules: NotificationRules {
        NotificationRules(needsYou: notifyNeedsYou, error: notifyError, done: notifyDone)
    }

    /// The first-run card offers to connect an agent until one is connected or the user says "Not now".
    public nonisolated static func offersConnect(anyConnected: Bool, anyConnectable: Bool, dismissed: Bool) -> Bool {
        anyConnectable && !anyConnected && !dismissed
    }
}
