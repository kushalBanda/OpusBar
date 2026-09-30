import Foundation
import Observation
import OpusBarCore
import OpusBarWire

/// Usage and plan limits for the menu bar, the dropdown strip and the Usage and Spend pane. A private serial queue owns the store and the log watcher: the first
/// scan reads 90 days of logs there, then file events and dropdown opens read only what was appended.
/// The main thread only receives finished totals.
@MainActor @Observable
final class UsageModel {
    nonisolated static let window: TimeInterval = 86_400

    /// One summary per range; empty until the first scan finishes.
    private(set) var summaries: [UsageRange: UsageSummary] = [:]

    /// Nil until the first scan finishes.
    var last24h: UsageTotals? { summaries[.day]?.total }

    /// Plan limits per account: each Claude profile's cache from Claude Code, and Codex's rollouts. Claude
    /// accounts first. Empty when none is known.
    private(set) var limits: [UsageLimits] = []

    @ObservationIgnored private let worker: UsageWorker

    init(claudeRoots: @escaping @Sendable () -> [URL], codexRoots: @escaping @Sendable () -> [URL],
         claudeAccountFiles: @escaping @Sendable () -> [URL], prices: UsagePriceList = UsageModel.bundledPrices()) {
        worker = UsageWorker(claudeRoots: claudeRoots, codexRoots: codexRoots, claudeAccountFiles: claudeAccountFiles,
                             prices: prices)
    }

    /// First scan, then watching.
    func start() {
        worker.start { [weak self] summaries, limits in
            guard let self else { return }
            Task { @MainActor in
                if self.summaries != summaries { self.summaries = summaries }
                if self.limits != limits { self.limits = limits }
            }
        }
    }

    /// Dropdown opened: pick up files the watcher can't see (new profile roots) and move the 24 h window.
    func refresh() { worker.refresh() }

    /// `usage-prices.json` from the app's resources (or the SwiftPM bundle under `swift run`). A missing or
    /// broken list leaves every reply unpriced rather than guessed.
    nonisolated static func bundledPrices() -> UsagePriceList {
        let dev = Bundle(url: Bundle.main.bundleURL.appending(path: "OpusBar_OpusBar.bundle"))
        guard let url = Bundle.main.url(forResource: "usage-prices", withExtension: "json")
                ?? dev?.url(forResource: "usage-prices", withExtension: "json"),
              let data = try? Data(contentsOf: url), let list = UsagePriceList.decode(data)
        else {
            NSLog("OpusBar: usage-prices.json missing or invalid; usage shows tokens without cost")
            return .empty
        }
        return list
    }
}

/// Everything here runs on `queue`; `UsageStore` is not thread-safe.
private final class UsageWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "OpusBar.usage", qos: .utility)
    private let store: UsageStore
    private var watcher: UsageLogWatcher?
    private var watching: [String] = []
    /// A refresh is queued and not yet run: further requests join it.
    private var refreshQueued = false
    private var publish: (@Sendable ([UsageRange: UsageSummary], [UsageLimits]) -> Void)?
    private let claudeLimits: ClaudeCodeLimitsReader
    /// Windows renew and Claude Code rewrites its cache without a log changing: look again each minute.
    private var clock: DispatchSourceTimer?

    init(claudeRoots: @escaping @Sendable () -> [URL], codexRoots: @escaping @Sendable () -> [URL],
         claudeAccountFiles: @escaping @Sendable () -> [URL], prices: UsagePriceList) {
        store = UsageStore(claudeRoots: claudeRoots, codexRoots: codexRoots, prices: prices)
        claudeLimits = ClaudeCodeLimitsReader(files: claudeAccountFiles)
    }

    func start(publish: @escaping @Sendable ([UsageRange: UsageSummary], [UsageLimits]) -> Void) {
        queue.async { [self] in
            self.publish = publish
            let clock = DispatchSource.makeTimerSource(queue: queue)
            clock.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(10))
            clock.setEventHandler { [weak self] in self?.send() }
            clock.resume()
            self.clock = clock
            watcher = UsageLogWatcher(queue: queue) { [weak self] paths, rescan in
                guard let self else { return }
                if rescan { runRefresh() } else { store.read(paths: paths); send() }
                #if DEBUG
                let totals = store.totals(since: Date().addingTimeInterval(-UsageModel.window))
                NSLog("OpusBar usage event: %d path(s), rescan=%d; 24 h now %d replies, %.2f USD", paths.count,
                      rescan ? 1 : 0, totals.replies, totals.cost)
                #endif
            }
            // The 24 h figures first (files changed in two days), so the menu has them within moments of
            // launch; the longer ranges follow when the 90-day read ends.
            #if DEBUG
            let started = Date()
            #endif
            store.refresh(recent: 2 * 86_400)
            send(ranges: [.day])
            #if DEBUG
            NSLog("OpusBar usage: 24 h ready in %.0f ms", Date().timeIntervalSince(started) * 1000)
            #endif
            runRefresh()
        }
    }

    func refresh() {
        queue.async { [self] in
            guard !refreshQueued else { return }
            refreshQueued = true
            queue.async { [self] in runRefresh() }
        }
    }

    private func runRefresh() {
        refreshQueued = false
        #if DEBUG
        let started = Date()
        let before = store.bytesRead
        #endif
        store.refresh()
        if store.watchedRoots != watching {
            watching = store.watchedRoots
            watcher?.start(watching)
        }
        #if DEBUG
        let totals = store.totals(since: Date().addingTimeInterval(-UsageModel.window))
        NSLog("OpusBar usage: %ld replies, %.2f USD, %ld tokens (24 h); read %.1f MB in %.0f ms, %ld records held",
              totals.replies, totals.cost, totals.tokens.total, Double(store.bytesRead - before) / 1e6,
              Date().timeIntervalSince(started) * 1000, store.records.count)
        for agent in AgentKind.allCases {
            var held = UsageTotals()
            for record in store.records where record.agent == agent { held.add(record) }
            NSLog("OpusBar usage held %@: %ld replies, %.2f USD, %ld tokens, %ld unpriced", agent.rawValue, held.replies,
                  held.cost, held.tokens.total, held.unpriced)
        }
        #endif
        send()
    }

    /// Every range and the limits at once: a few milliseconds over months of replies, at most about once a second.
    /// `ranges` narrows it during the first read, when only the recent files are in.
    private func send(ranges: [UsageRange] = UsageRange.allCases) {
        let now = Date()
        let records = store.records
        var summaries: [UsageRange: UsageSummary] = [:]
        for range in ranges {
            summaries[range] = UsageSummary.make(records: records, range: range, now: now)
        }
        let limits = (claudeLimits.read() + [store.codexLimits].compactMap { $0 }).map { $0.asOf(now) }
        publish?(summaries, limits)
    }
}
