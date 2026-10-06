import AppKit
import OpusBarCore
import SwiftUI

/// Menu bar item: the pixel cat for the loudest session state, plus a badge.
/// Frames advance only while the cat animates, and stop 30 s after the last session change.
@MainActor
final class StatusItemController: NSObject {
    static let activityWindow: TimeInterval = 30

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    /// The dropdown is a real menu with one item hosting the SwiftUI list. While a menu is open macOS
    /// keeps the menu bar on screen, also in a full-screen Space where a popover would vanish with it,
    /// and it handles outside clicks and Esc itself.
    private let menu = NSMenu()
    private var content: MenuHostingView<SessionListView>!
    private let store: SessionStore
    /// Called each time the dropdown opens (fresh discovery pass).
    private let onOpen: () -> Void
    private let settings: SettingsWindowController
    private let preferences: Preferences
    private let layout = PopoverLayout()
    private(set) var isMenuShown = false

    private var aggregate = Aggregate(state: nil, needsYouCount: 0, activeCount: 0)
    private var animation = CatAnimation.idle
    private var frameIndex = 0
    private var lastActivity = Date()
    private var frameTimer: Timer?
    private var catAnimates = true
    private var look = MenuBarLook()
    /// Composed status images keyed by frame + badge, so animation just swaps cached images.
    private var imageCache: [String: NSImage] = [:]

    init(store: SessionStore, preferences: Preferences, hooks: AgentHooksModel,
         usage: UsageModel, updater: Updater, settings: SettingsWindowController, onOpen: @escaping () -> Void = {}) {
        self.store = store
        self.preferences = preferences
        self.settings = settings
        self.onOpen = onOpen
        super.init()
        content = MenuHostingView(rootView: SessionListView(store: store, preferences: preferences, hooks: hooks,
                                                           usage: usage, updater: updater, layout: layout,
                                                           openSettings: { [weak self] pane in
            self?.menu.cancelTracking()
            self?.settings.show(pane)
        }))
        content.fit()
        let item = NSMenuItem()
        item.view = content
        menu.addItem(item)
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imageScaling = .scaleNone
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        // The bar is taller on a notch display: redraw at the right size when displays change.
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        observeStore()
        #if DEBUG
        // `--stress-fit <n>` repeats what opening the menu does offscreen; `--stress-menu <n>` really opens and
        // closes the menu n times (it shows on screen). Both hunt the menu-open crash.
        let stressArgs = ProcessInfo.processInfo.arguments
        for flag in ["--stress-fit", "--stress-menu"] {
            if let i = stressArgs.firstIndex(of: flag), i + 1 < stressArgs.count, let count = Int(stressArgs[i + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.stress(real: flag == "--stress-menu", left: count, total: count)
                }
            }
        }
        // `--dump-menu <png>` renders the dropdown offscreen after 5 s, for checks without opening the menu.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--dump-menu"), i + 1 < args.count {
            let path = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                let view = NSHostingView(rootView: SessionListView(store: store, preferences: preferences, hooks: hooks,
                                                                   usage: usage, updater: updater, layout: PopoverLayout()))
                let size = view.fittingSize
                let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = view
                window.orderFrontRegardless()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    view.layoutSubtreeIfNeeded()
                    if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    }
                    window.orderOut(nil)
                    NSLog("OpusBar dumped menu to %@", path)
                }
            }
        }
        #endif
    }

    /// Any session change counts as activity; re-arms itself after each change.
    /// The Motion setting is tracked too, so turning it off stops the cat at once.
    private func observeStore() {
        let (_, aggregate, animates, _, poses, look) = withObservationTracking {
            (store.state, store.aggregate, preferences.animateCat, preferences.coat, preferences.poses, preferences.menuBar)
        } onChange: {
            Task { @MainActor [weak self] in self?.observeStore() }
        }
        self.aggregate = aggregate
        lastActivity = Date()
        let next = CatAnimation(pose: look.pose(for: aggregate.state, poses: poses))
        if next != animation || frameTimer == nil || animates != catAnimates || look.pace != self.look.pace {
            animation = next
            catAnimates = animates
            self.look = look
            restartFrames()
        } else {
            self.look = look
            draw()
        }
    }

    @objc private func displayOptionsChanged() {
        restartFrames()
    }

    private func restartFrames() {
        frameTimer?.invalidate()
        frameTimer = nil
        frameIndex = 0
        draw()
        guard animation.isAnimated, catAnimates, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let interval = look.frameInterval(for: animation.interval)
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
        let cat = CatSheet.sheet(for: preferences.coat).frame(col: frame.col, row: frame.row)
        let badge = look.showsBadge ? Self.badge(for: aggregate) : nil
        let alpha = look.alpha(hasSessions: aggregate.state != nil)
        let points = CGFloat(look.catPoints(barThickness: barHeight))
        let key = "\(preferences.coat.rawValue),\(frame.col),\(frame.row),\(badge?.text ?? "-"),\(alpha),\(points)"
        if let cached = imageCache[key] {
            if button.image !== cached { button.image = cached }
            button.setAccessibilityLabel(accessibilityLabel)
            return
        }
        let size = NSSize(width: badge == nil ? points + 2 : points + 9, height: points + 2)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Crisp pixels at 1:1 and up; smooth below that (a 1x display), where nearest neighbour drops rows.
            let scale = context.userSpaceToDeviceSpaceTransform.a
            context.interpolationQuality = points * scale < CGFloat(CatSheet.framePixels) ? .high : .none
            if let cat {
                context.setAlpha(alpha)
                context.draw(cat, in: CGRect(x: 1, y: 1, width: points, height: points))
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

    /// The real height of the menu bar the icon sits in. `NSStatusBar.system.thickness` always says 22,
    /// also on notch displays where the bar is much taller, which capped Large at Medium's size.
    private var barHeight: Double {
        let window = statusItem.button?.window?.frame.height ?? 0
        return window > 0 ? window : NSStatusBar.system.thickness
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

    #if DEBUG
    private func stress(real: Bool, left: Int, total: Int) {
        guard left > 0 else { NSLog("OpusBar stress finished: %d", total); return }
        if real {
            // A Task would wait for the main queue, which the menu's tracking loop doesn't drain:
            // the menu stayed open and the stress run stalled. A run loop timer fires during tracking.
            let close = Timer(timeInterval: 0.25, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.menu.cancelTracking() }
            }
            RunLoop.main.add(close, forMode: .common)
            statusItem.button?.performClick(nil) // returns when the menu closes
        } else {
            menuWillOpen(menu)
            menuDidOpen()
            menuDidClose(menu)
        }
        if (total - left + 1) % 100 == 0 { NSLog("OpusBar stress: %d", total - left + 1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (real ? 0.1 : 0.01)) { [weak self] in
            self?.stress(real: real, left: left - 1, total: total)
        }
    }
    #endif

    /// Opens the dropdown without a click (notification click, and `--menu` in debug builds).
    func showMenu() {
        guard !isMenuShown else { return }
        statusItem.button?.performClick(nil)
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuShown = true
        // Don't touch SwiftUI while the menu is being built. Every crash report (SIGSEGV in AttributeGraph,
        // or an objc_initWeak abort) was a synchronous measure here, also with `onOpen` moved after it.
        // The menu opens at the last measured height; one run loop turn later the view is in the menu's
        // window, and the refit resizes the open menu if anything changed. Common modes, so the block
        // runs during menu tracking.
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated { self?.menuDidOpen() }
        }
    }

    private func menuDidOpen() {
        guard isMenuShown else { return }
        if let screen = statusItem.button?.window?.screen ?? NSScreen.main, layout.screenHeight != screen.visibleFrame.height {
            layout.screenHeight = screen.visibleFrame.height
        }
        #if DEBUG
        // `--screen-height <pt>` lays the menu out as if on a screen that tall, for screenshots that don't scroll.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--screen-height"), i + 1 < args.count, let height = Double(args[i + 1]) {
            layout.screenHeight = height
        }
        #endif
        onOpen()
        content.fit()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuShown = false
        // Done is "finished, not yet seen": once the menu showed it, it goes back to Idle.
        store.acknowledgeDone(seenAt: Date())
    }
}

/// Hosts SwiftUI in a menu item. A menu lays out a custom row from the view's intrinsic height, not
/// its frame, so the row height is measured from the content and reported there whenever the content
/// changes (a card opens, Idle unfolds, sessions come and go). Reporting it only through the frame
/// leaves the row at its open-time height and clips the top of the list.
final class MenuHostingView<Content: View>: NSHostingView<Content> {
    private var rowHeight: CGFloat?
    /// True while `fit` measures, so the invalidations it causes don't schedule another pass.
    private var measuring = false
    /// A refit is already queued: further invalidations join it.
    private var fitQueued = false

    override var intrinsicContentSize: NSSize {
        guard let rowHeight else { return super.intrinsicContentSize }
        return NSSize(width: NSView.noIntrinsicMetric, height: rowHeight)
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !measuring, !fitQueued else { return }
        fitQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.fitQueued = false
            self?.fit()
        }
    }

    func fit() {
        measuring = true
        defer { measuring = false }
        // Measure the content itself, not the height last reported.
        let reported = rowHeight
        rowHeight = nil
        let size = fittingSize
        let height = ceil(size.height)
        guard size.width > 0, height > 0 else { rowHeight = reported; return }
        rowHeight = height
        guard reported != height || frame.size != NSSize(width: size.width, height: height) else { return }
        setFrameSize(NSSize(width: size.width, height: height))
        super.invalidateIntrinsicContentSize()
        layoutSubtreeIfNeeded()
        // An open menu doesn't resize its window for a new intrinsic height on its own: the row grows
        // upward past the top (clipped) or shrinks leaving a gap above. Telling the menu the item
        // changed makes it lay out the window again from the top.
        if let item = enclosingMenuItem, let menu = item.menu {
            menu.itemChanged(item)
        } else {
            superview?.layoutSubtreeIfNeeded()
        }
    }
}
