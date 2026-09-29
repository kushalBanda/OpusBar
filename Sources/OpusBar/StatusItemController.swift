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
    /// Menu bar cat size. 20 pt (40 px on Retina from the 32 px frame) reads better than the 1:1 16 pt;
    /// nearest-neighbor keeps the pixels hard-edged.
    static let catPoints: CGFloat = 20

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: SessionStore
    /// Called each time the dropdown opens (fresh discovery pass).
    private let onOpen: () -> Void
    private let settings: SettingsWindowController
    private let preferences: Preferences
    private let layout = PopoverLayout()
    /// Local key monitor, installed only while the popover is open, so Esc closes it.
    private var escMonitor: Any?

    private var aggregate = Aggregate(state: nil, needsYouCount: 0, activeCount: 0)
    private var animation = CatAnimation.idle
    private var frameIndex = 0
    private var lastActivity = Date()
    private var frameTimer: Timer?
    private var catAnimates = true
    /// Composed status images keyed by frame + badge, so animation just swaps cached images.
    private var imageCache: [String: NSImage] = [:]

    init(store: SessionStore, preferences: Preferences, hooks: AgentHooksModel, entitlements: Entitlements,
         settings: SettingsWindowController, onOpen: @escaping () -> Void = {}) {
        self.store = store
        self.preferences = preferences
        self.settings = settings
        self.onOpen = onOpen
        super.init()
        popover.behavior = .transient // closes on any click outside
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: SessionListView(store: store, preferences: preferences, hooks: hooks,
                                                                                       entitlements: entitlements, layout: layout) { [weak self] pane in
            self?.popover.performClose(nil)
            self?.settings.show(pane)
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
    /// The Motion setting is tracked too, so turning it off stops the cat at once.
    private func observeStore() {
        let (_, aggregate, animates) = withObservationTracking {
            (store.state, store.aggregate, preferences.animateCat)
        } onChange: {
            Task { @MainActor [weak self] in self?.observeStore() }
        }
        self.aggregate = aggregate
        lastActivity = Date()
        let next = CatAnimation.for(aggregate.state)
        if next != animation || frameTimer == nil || animates != catAnimates {
            animation = next
            catAnimates = animates
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
        guard animation.isAnimated, catAnimates, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
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
        let size = NSSize(width: badge == nil ? Self.catPoints + 2 : Self.catPoints + 9, height: Self.catPoints + 2)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.interpolationQuality = .none
            if let cat {
                context.setAlpha(dimmed ? 0.5 : 1)
                context.draw(cat, in: CGRect(x: 1, y: 1, width: Self.catPoints, height: Self.catPoints))
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

    var isMenuShown: Bool { popover.isShown }

    /// Opens the dropdown without a click (notification click, and `--menu` in debug builds).
    func showMenu() {
        guard !popover.isShown, let button = statusItem.button else { return }
        toggle(button)
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Accessory apps are never active on their own; without this the popover can't take Esc.
            onOpen()
            if let screen = sender.window?.screen ?? NSScreen.main { layout.screenHeight = screen.visibleFrame.height }
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
        // Done is "finished, not yet seen": once the menu showed it, it goes back to Idle.
        store.acknowledgeDone(seenAt: Date())
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }
}
