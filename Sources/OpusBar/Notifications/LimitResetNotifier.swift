import Foundation
import Observation
import OpusBarCore
import UserNotifications

/// Schedules a macOS notification for the moment each used plan window renews, per the user's toggles.
/// macOS delivers it on time from a date trigger; each change to the limits or the toggles brings the
/// pending set in line with `LimitResetPlanner`. Clicks open the menu through `SessionNotifier`, the
/// notification center's delegate.
@MainActor
final class LimitResetNotifier {
    private let usage: UsageModel
    private let preferences: Preferences
    /// What is scheduled now, by identifier, so an unchanged reset is not scheduled again.
    private var scheduled: [String: Date] = [:]

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    init(usage: UsageModel, preferences: Preferences) {
        self.usage = usage
        self.preferences = preferences
        // Resets scheduled by an earlier run follow readings that may have changed since.
        center?.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter { $0.hasPrefix(LimitResetPlanner.identifierPrefix) }
            Task { @MainActor in
                self.center?.removePendingNotificationRequests(withIdentifiers: old)
                self.observe()
            }
        }
    }

    private func observe() {
        let plan = withObservationTracking {
            LimitResetPlanner.plan(usage.limits, muted: preferences.limitResetMuted, enabled: preferences.notifyLimitReset,
                                   now: Date())
        } onChange: {
            Task { @MainActor [weak self] in self?.observe() }
        }
        apply(plan)
    }

    private func apply(_ plan: [LimitResetNotice]) {
        guard let center else { return }
        let wanted = Dictionary(plan.map { ($0.id, $0.date) }, uniquingKeysWith: { first, _ in first })
        let gone = scheduled.keys.filter { wanted[$0] == nil }
        if !gone.isEmpty { center.removePendingNotificationRequests(withIdentifiers: gone) }
        let changed = plan.filter { scheduled[$0.id] != $0.date }
        scheduled = wanted
        guard !changed.isEmpty else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for notice in changed {
                let content = UNMutableNotificationContent()
                content.title = notice.title
                content.body = notice.body
                content.threadIdentifier = "limits"
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, notice.date.timeIntervalSinceNow), repeats: false)
                center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger))
            }
        }
    }
}
