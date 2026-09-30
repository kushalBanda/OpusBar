import Foundation
import Observation
import OpusBarCore
import UserNotifications

/// Schedules a macOS notification for the moment each used plan window renews, per the user's toggles.
/// macOS delivers it on time from a date trigger; each change to the limits or the toggles brings the
/// pending set in line with `LimitResetPlanner`. Also warns at once when a window reaches 80 % or 95 %
/// used (`LimitWarningPlanner`), once per threshold per window period, remembered across launches.
/// Clicks open the menu through `SessionNotifier`, the notification center's delegate.
@MainActor
final class LimitResetNotifier {
    private let usage: UsageModel
    private let preferences: Preferences
    /// What is scheduled now, by identifier, so an unchanged reset is not scheduled again.
    private var scheduled: [String: Date] = [:]
    private static let sentKey = "limitWarningsSent"
    /// Warnings already sent, for windows that have not renewed yet.
    private var sent: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.sentKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: Self.sentKey) }
    }

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
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--test-limit-notices") { self.sendSamples() }
                #endif
            }
        }
    }

    #if DEBUG
    /// `--test-limit-notices`: a sample warning now and a sample reset in 10 s, through the same path as real ones.
    private func sendSamples() {
        let now = Date()
        warn([LimitWarning(notice: LimitResetNotice(id: "limitwarn.sample", date: now, title: "Claude Code limit 80% used",
                                                    body: "Your 5 h limit is 82% used. It resets in 2h. (sample)"), keys: [])], now: now)
        apply(LimitResetPlanner.plan(usage.limits, muted: preferences.limitResetMuted, enabled: preferences.notifyLimitReset, now: now)
              + [LimitResetNotice(id: LimitResetPlanner.identifierPrefix + "sample", date: now.addingTimeInterval(10),
                                  title: "Claude Code limit reset", body: "Your 5 h limit is back to 100%. (sample)")])
    }
    #endif

    private func observe() {
        let now = Date()
        let (plan, warnings) = withObservationTracking {
            (LimitResetPlanner.plan(usage.limits, muted: preferences.limitResetMuted, enabled: preferences.notifyLimitReset,
                                    now: now),
             LimitWarningPlanner.due(usage.limits, muted: preferences.limitResetMuted, enabled: preferences.notifyLimitWarning,
                                     sent: sent, now: now))
        } onChange: {
            Task { @MainActor [weak self] in self?.observe() }
        }
        apply(plan)
        warn(warnings, now: now)
    }

    private func warn(_ warnings: [LimitWarning], now: Date) {
        // Marked sent even when macOS declines, so a denied permission doesn't queue a burst for later.
        var sent = LimitWarningPlanner.unexpired(sent, now: now)
        for warning in warnings { sent.formUnion(warning.keys) }
        self.sent = sent
        guard let center, !warnings.isEmpty else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for warning in warnings {
                center.add(UNNotificationRequest(identifier: warning.notice.id, content: Self.content(warning.notice), trigger: nil))
            }
        }
    }

    nonisolated private static func content(_ notice: LimitResetNotice) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.threadIdentifier = "limits"
        content.sound = .default
        return content
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
                let content = Self.content(notice)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, notice.date.timeIntervalSinceNow), repeats: false)
                center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger))
            }
        }
    }
}
