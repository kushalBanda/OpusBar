import AppKit
import ApplicationServices
import Observation
import OpusBarCore

/// The two permissions a notice click can use, read live from macOS for Settings. Nothing is saved.
/// Without either one, a click still brings the session's app forward.
@MainActor @Observable
final class FocusPermissions {
    enum Grant: Equatable {
        case granted
        /// Not granted yet, or turned off earlier: macOS gives the same answer for both when we don't ask.
        case notGranted
        /// Asked, and the answer was no. Only System Settings can change it now.
        case denied
        /// The target app isn't open, so macOS can't say. It asks on the first click that needs it.
        case appNotRunning
    }

    private(set) var accessibility: Grant = .notGranted
    private(set) var terminalAutomation: Grant = .appNotRunning
    private(set) var asking = false

    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")

    func refresh() {
        accessibility = AXIsProcessTrusted() ? .granted : .notGranted
        let id = ScriptableTerminal.terminalApp.bundleId
        Task {
            let status = await Self.automationStatus(bundleId: id, ask: false)
            // A no from an ask outranks the silent check, which can't tell "never asked" from "turned off".
            if !(terminalAutomation == .denied && status == -1744) { terminalAutomation = Self.grant(status) }
        }
    }

    /// The system prompt. macOS shows it once; after a no, it only opens Settings.
    func requestAccessibility() {
        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if !trusted, let url = Self.accessibilitySettingsURL { NSWorkspace.shared.open(url) }
        accessibility = trusted ? .granted : .notGranted
    }

    /// Asks macOS for Automation of Terminal. The prompt blocks its thread, so it runs off the main one.
    func requestTerminalAutomation() {
        guard !asking else { return }
        asking = true
        let id = ScriptableTerminal.terminalApp.bundleId
        Task {
            let status = await Self.automationStatus(bundleId: id, ask: true)
            terminalAutomation = Self.grant(status)
            asking = false
        }
    }

    func openAutomationSettings() {
        if let url = Self.automationSettingsURL { NSWorkspace.shared.open(url) }
    }

    /// 0 granted, -1743 denied, -1744 needs consent (or was turned off), -600 app not running.
    private nonisolated static func automationStatus(bundleId: String, ask: Bool) async -> OSStatus {
        await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
            guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
            return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        }.value
    }

    private static func grant(_ status: OSStatus) -> Grant {
        switch status {
        case noErr: .granted
        case OSStatus(errAEEventNotPermitted): .denied
        case OSStatus(procNotFound): .appNotRunning
        default: .notGranted
        }
    }
}
