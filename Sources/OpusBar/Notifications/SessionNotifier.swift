import AppKit
import Observation
import OpusBarCore
import os
import UserNotifications

/// Posts macOS notifications when sessions enter needs-you, error or done (per the user's toggles).
/// Watches the store, diffs each change through `NotificationPlanner`, and asks for permission the
/// first time something would be posted.
@MainActor @Observable
final class SessionNotifier: NSObject {
    enum Access: Equatable {
        /// Running outside an app bundle (`swift run`): UserNotifications needs a bundle identifier.
        case unavailable
        case notAsked
        case allowed
        /// Allowed, but macOS shows nothing: the alert style is None, so notices land only in Notification Center.
        case silent
        case denied
    }

    nonisolated static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "OpusBar", category: "notifications")

    /// The Settings test button: one test at a time, then a short "Sent" before it can go again.
    enum TestState: Equatable {
        case ready, sending, sent
    }

    private(set) var access: Access = .notAsked
    private(set) var testState: TestState = .ready

    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let preferences: Preferences
    /// While the dropdown is open the user already sees every card; posting then is noise.
    @ObservationIgnored private let isMenuShown: () -> Bool
    @ObservationIgnored private let openMenu: () -> Void
    @ObservationIgnored private var last = SessionsState()

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    init(store: SessionStore, preferences: Preferences, isMenuShown: @escaping () -> Bool, openMenu: @escaping () -> Void) {
        self.store = store
        self.preferences = preferences
        self.isMenuShown = isMenuShown
        self.openMenu = openMenu
        super.init()
        last = store.state
        center?.delegate = self
        // Sessions from a previous run are gone, so are the states their notifications announced.
        center?.getDeliveredNotifications { delivered in
            let sessions = delivered.map(\.request.identifier).filter { $0.hasPrefix("session.") }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: sessions)
        }
        refreshAccess()
        if preferences.anyNotificationOn { requestAccess() }
        observe()
    }

    /// Asks macOS now, not at the first notice: a prompt missed while a session runs (Focus, a hidden
    /// banner) would silently drop that notice. Does nothing once the user has answered.
    func requestAccess() {
        guard let center else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                Self.logAuthorization(granted: granted, error: error)
                Task { @MainActor in self.refreshAccess() }
            }
        }
    }

    /// The Settings button for a prompt the user never answered: asks again, then reads what macOS decided.
    func askNow() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Self.logAuthorization(granted: granted, error: error)
            Task { @MainActor in self.refreshAccess() }
        }
    }

    func refreshAccess() {
        guard let center else { access = .unavailable; return }
        center.getNotificationSettings { settings in
            let access: Access = switch settings.authorizationStatus {
            case .notDetermined: .notAsked
            case .denied: .denied
            default: settings.alertStyle == .none ? .silent : .allowed
            }
            Task { @MainActor in self.access = access }
        }
    }

    /// Settings' "Send a test": a needs-you notice through the same path as real ones. Repeated clicks
    /// are ignored until the last test is out and a short pause has passed; every test shares one
    /// identifier, so even a fast second one replaces the first instead of stacking.
    func sendTest() {
        guard let center, testState == .ready else { return }
        testState = .sending
        let notice = SessionNotice(sessionId: "test", state: .needsAttention, title: "OpusBar needs you",
                                   body: "Claude Code · This is a test notification", thread: "test")
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Self.logAuthorization(granted: granted, error: error)
            Task { @MainActor in
                self.refreshAccess()
                // Not allowed: the access tile says why, so the button is ready again at once.
                guard granted else { self.testState = .ready; return }
                self.post(notice, center: center) { delivered in
                    self.testState = delivered ? .sent : .ready
                    guard delivered else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        self.testState = .ready
                    }
                }
            }
        }
    }

    /// The deep link to OpusBar's own row in System Settings > Notifications.
    static var settingsURL: URL? {
        let id = Bundle.main.bundleIdentifier.map { "?id=" + $0 } ?? ""
        return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension" + id)
    }

    nonisolated private static func logAuthorization(granted: Bool, error: Error?) {
        if let error {
            log.error("permission request failed: \(error.localizedDescription, privacy: .public)")
        } else if !granted {
            log.notice("permission not granted; notices are dropped until it is turned on in System Settings")
        }
    }

    private func observe() {
        let state = withObservationTracking { store.state } onChange: {
            Task { @MainActor [weak self] in self?.observe() }
        }
        let plan = NotificationPlanner.plan(old: last, new: state, rules: preferences.notificationRules)
        last = state
        apply(plan)
    }

    private func apply(_ plan: NotificationPlanner.Plan) {
        guard let center else { return }
        if !plan.clear.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: plan.clear.map(Self.identifier))
        }
        let posts = isMenuShown() ? [] : plan.post
        guard !posts.isEmpty else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Self.logAuthorization(granted: granted, error: error)
            Task { @MainActor in
                self.refreshAccess()
                guard granted else { return }
                posts.forEach { self.post($0, center: center) }
            }
        }
    }

    private func post(_ notice: SessionNotice, center: UNUserNotificationCenter,
                      completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.threadIdentifier = notice.thread
        // Done is informational; only needs-you and errors make a sound.
        if notice.state != .done { content.sound = .default }
        if let cat = NotificationCat.attachment(state: notice.state, coat: preferences.coat, poses: preferences.poses) {
            content.attachments = [cat]
        }
        center.add(UNNotificationRequest(identifier: Self.identifier(notice.sessionId), content: content, trigger: nil)) { error in
            if let error { Self.log.error("post failed: \(error.localizedDescription, privacy: .public)") }
            Task { @MainActor in completion(error == nil) }
        }
    }

    /// One identifier per session: a newer notification replaces the older one.
    private static func identifier(_ sessionId: String) -> String { "session." + sessionId }
}

extension SessionNotifier: UNUserNotificationCenterDelegate {
    /// Show banners even while OpusBar is the active app (e.g. Settings is open).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clicking a notification opens the dropdown.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            self.openMenu()
            completionHandler()
        }
    }
}
