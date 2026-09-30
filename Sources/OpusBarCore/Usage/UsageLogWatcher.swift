import CoreServices
import Foundation

/// File-level change events for the log folders, delivered on `queue`. The system coalesces bursts over
/// `latency`, so a busy agent costs about one callback a second. `rescan` is true when events were
/// dropped or a root moved: the owner then refreshes everything.
public final class UsageLogWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue: DispatchQueue
    private let latency: CFTimeInterval
    private let handler: (_ paths: [String], _ rescan: Bool) -> Void

    public init(queue: DispatchQueue, latency: CFTimeInterval = 1.0,
                handler: @escaping (_ paths: [String], _ rescan: Bool) -> Void) {
        self.queue = queue
        self.latency = latency
        self.handler = handler
    }

    deinit { stop() }

    /// Starts watching `paths` (replacing any earlier stream); false when nothing could be watched.
    @discardableResult
    public func start(_ paths: [String]) -> Bool {
        stop()
        guard !paths.isEmpty else { return false }
        // The stream retains the watcher, so a callback already queued never outlives it.
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<UsageLogWatcher>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<UsageLogWatcher>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<UsageLogWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
                                               | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped)
            watcher.handler(changed, (0..<count).contains { flags[$0] & lost != 0 })
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                                             | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, paths as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return false }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return false
        }
        stream = created
        return true
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
