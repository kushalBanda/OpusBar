import AppKit
import OpusBarCore
import SwiftUI

/// Menu bar item: the pixel cat for the loudest session state, plus a badge.
/// Frames advance only while the cat animates, and stop 30 s after the last session change.
@MainActor
final class StatusItemController: NSObject {
    static let activityWindow: TimeInterval = 30
    /// Menu bar frames never tick faster than this; each tick costs a status bar redraw.
    static let minFrameInterval: TimeInterval = 0.25

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: SessionStore
    private let settings = SettingsWindowController()
    /// Local key monitor, installed only while the popover is open, so Esc closes it.
    private var escMonitor: Any?

    private var aggregate = Aggregate(state: nil, needsYouCount: 0, activeCount: 0)
    private var animation = CatAnimation.idle
    private var frameIndex = 0
    private var lastActivity = Date()
    private var frameTimer: Timer?
    /// Composed status images keyed by frame + badge, so animation just swaps cached images.
    private var imageCache: [String: NSImage] = [:]

    init(store: SessionStore) {
        self.store = store
        super.init()
        popover.behavior = .transient // closes on any click outside
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: SessionListView(store: store) { [weak self] in
            self?.popover.performClose(nil)
            self?.settings.show()
        })
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle(_:))
            button.imageScaling = .scaleNone
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        observeStore()
    }

    /// Any session change counts as activity; re-arms itself after each change.
    private func observeStore() {
        let (_, aggregate) = withObservationTracking {
            (store.state, store.aggregate)
        } onChange: {
            Task { @MainActor [weak self] in self?.observeStore() }
        }
        self.aggregate = aggregate
        lastActivity = Date()
        let next = CatAnimation.for(aggregate.state)
        if next != animation || frameTimer == nil {
            animation = next
            restartFrames()
        } else {
            draw()
        }
    }

    @objc private func displayOptionsChanged() {
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        restartFrames()
    }

    private func restartFrames() {
        frameTimer?.invalidate()
        frameTimer = nil
        frameIndex = 0
        draw()
        guard animation.isAnimated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let interval = max(animation.interval, Self.minFrameInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer.tolerance = interval / 10
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func tick() {
        if Date().timeIntervalSince(lastActivity) > Self.activityWindow {
            // Quiet for a while: hold still until the next event. Idle CPU goes back to zero.
            frameTimer?.invalidate()
            frameTimer = nil
            frameIndex = 0
        } else {
            frameIndex += 1
        }
        draw()
    }

    private func draw() {
        guard let button = statusItem.button else { return }
        let frame = animation.frames[frameIndex % animation.frames.count]
        let cat = CatSheet.shared.frame(col: frame.col, row: frame.row)
        let badge = Self.badge(for: aggregate)
        let dimmed = aggregate.state == nil
        let key = "\(frame.col),\(frame.row),\(badge?.text ?? "-"),\(dimmed)"
        if let cached = imageCache[key] {
            if button.image !== cached { button.image = cached }
            button.setAccessibilityLabel(accessibilityLabel)
            return
        }
        let size = NSSize(width: badge == nil ? 18 : 25, height: 18)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.interpolationQuality = .none
            if let cat {
                context.setAlpha(dimmed ? 0.5 : 1)
                // 16 pt = the 32 px frame 1:1 on Retina.
                context.draw(cat, in: CGRect(x: 1, y: 1, width: 16, height: 16))
                context.setAlpha(1)
            }
            if let badge {
                let circle = CGRect(x: size.width - 12, y: size.height - 12, width: 11, height: 11)
                badge.color.setFill()
                NSBezierPath(ovalIn: circle).fill()
                let text = NSAttributedString(string: badge.text, attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: NSColor(red: 0.173, green: 0.18, blue: 0.165, alpha: 1),
                ])
                let textSize = text.size()
                text.draw(at: CGPoint(x: circle.midX - textSize.width / 2, y: circle.midY - textSize.height / 2))
            }
            return true
        }
        image.isTemplate = false
        imageCache[key] = image
        button.image = image
        button.setAccessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let state = aggregate.state else { return "OpusBar, no sessions" }
        if aggregate.needsYouCount > 0 { return "OpusBar, \(aggregate.needsYouCount) session(s) need you" }
        return "OpusBar, \(state.label)"
    }

    static func badge(for aggregate: Aggregate) -> (text: String, color: NSColor)? {
        switch aggregate.state {
        case .error: ("!", SessionState.error.badgeColor)
        case .needsAttention: ("\(aggregate.needsYouCount)", SessionState.needsAttention.badgeColor)
        case .done: ("✓", SessionState.done.badgeColor)
        default: nil
        }
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Accessory apps are never active on their own; without this the popover can't take Esc.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            self?.popover.performClose(nil)
            return nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }
}
