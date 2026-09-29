import AppKit
import Observation
import OpusBarCore
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
        case denied
    }

    private(set) var access: Access = .notAsked

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
        center?.removeAllDeliveredNotifications()
        refreshAccess()
        observe()
    }

    func refreshAccess() {
        guard let center else { access = .unavailable; return }
        center.getNotificationSettings { settings in
            let access: Access = switch settings.authorizationStatus {
            case .notDetermined: .notAsked
            case .denied: .denied
            default: .allowed
            }
            Task { @MainActor in self.access = access }
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
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.access = granted ? .allowed : .denied
                guard granted else { return }
                posts.forEach { self.post($0, center: center) }
            }
        }
    }

    private func post(_ notice: SessionNotice, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.threadIdentifier = notice.thread
        // Done is informational; only needs-you and errors make a sound.
        if notice.state != .done { content.sound = .default }
        center.add(UNNotificationRequest(identifier: Self.identifier(notice.sessionId), content: content, trigger: nil))
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
