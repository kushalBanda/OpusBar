import SwiftUI

@main
struct OpusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI needs one scene. The real Settings window is SettingsWindowController (opened from the dropdown).
        Settings { EmptyView() }
    }
}
