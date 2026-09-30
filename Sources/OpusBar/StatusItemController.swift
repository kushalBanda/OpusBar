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

    init(store: SessionStore, preferences: Preferences, hooks: AgentHooksModel, entitlements: Entitlements,
         settings: SettingsWindowController, onOpen: @escaping () -> Void = {}) {
        self.store = store
        self.preferences = preferences
        self.settings = settings
        self.onOpen = onOpen
        super.init()
        content = MenuHostingView(rootView: SessionListView(store: store, preferences: preferences, hooks: hooks,
                                                           entitlements: entitlements, layout: layout,
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
        observeStore()
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
        let points = CGFloat(look.catPoints(barThickness: NSStatusBar.system.thickness))
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

    /// Opens the dropdown without a click (notification click, and `--menu` in debug builds).
    func showMenu() {
        guard !isMenuShown else { return }
        statusItem.button?.performClick(nil)
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuShown = true
        onOpen()
        if let screen = statusItem.button?.window?.screen ?? NSScreen.main { layout.screenHeight = screen.visibleFrame.height }
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

    override var intrinsicContentSize: NSSize {
        guard let rowHeight else { return super.intrinsicContentSize }
        return NSSize(width: NSView.noIntrinsicMetric, height: rowHeight)
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !measuring else { return }
        DispatchQueue.main.async { [weak self] in self?.fit() }
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
