import Observation
import ServiceManagement

/// Start at login through the system's login items. macOS owns the state; the user can also flip it in
/// System Settings, so the toggle re-reads the status instead of caching a preference.
@MainActor @Observable
final class LaunchAtLogin {
    private(set) var isEnabled = false
    /// Shown under the toggle: approval needed, or why registering failed (e.g. running outside an app bundle).
    private(set) var note: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        note = status == .requiresApproval ? "Allow OpusBar in System Settings → General → Login Items." : nil
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            note = Bundle.main.bundleIdentifier == nil
                ? "Only works from OpusBar.app, not `swift run`."
                : "Couldn't change it: \(error.localizedDescription)"
        }
    }
}
