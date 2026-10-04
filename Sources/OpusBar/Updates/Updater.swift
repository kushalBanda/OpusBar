import AppKit
import Observation
import OpusBarCore

/// Finds and installs newer releases (ADR 23). One request to GitHub's "latest release" API a minute
/// after launch and then once a day, only while the setting is on; "Check Now" asks once whenever
/// clicked. Nothing about the user goes along: the request carries OpusBar's name and version only.
/// With "install automatically" on, a newer release is downloaded and verified in the background and
/// swapped in when OpusBar next quits; otherwise it installs only on a click. Either way only when the
/// zip's Ed25519 signature matches the key built into the app and the new app has our bundle id and the
/// promised version.
@MainActor @Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case available(UpdateRelease)
        /// Downloaded and verified; swaps in when OpusBar quits, or now on a click.
        case ready(UpdateRelease)
        case installing(UpdateRelease)
        case failed(String)
    }

    private(set) var state: State = .idle
    /// The release on offer, also while it installs or after a failed attempt.
    private(set) var offered: UpdateRelease?

    @ObservationIgnored private let preferences: Preferences
    /// The verified new app waiting in a temporary folder, and whether a swap is already under way.
    @ObservationIgnored private var staged: (release: UpdateRelease, app: URL)?
    @ObservationIgnored private var swapStarted = false
    @ObservationIgnored private var timer: Timer?

    /// Nil for a build without a version (`swift run`): it never checks on its own.
    static let current: AppVersion? = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)

    init(preferences: Preferences) {
        self.preferences = preferences
        // A note for another version (an update that was skipped or never finished) has nothing to say now.
        if let note = preferences.whatsNew, let current = Self.current, AppVersion(note.version) != current { preferences.whatsNew = nil }
        observe()
        #if DEBUG
        // `--update-now`: check at once and install what's found, for the end-to-end update test.
        if ProcessInfo.processInfo.arguments.contains("--update-now") { check(thenInstall: true) }
        #endif
    }

    /// GitHub's latest release; DEBUG `--update-feed <url>` points at a local copy for tests.
    private static var feedURL: URL {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--update-feed"), i + 1 < args.count, let url = URL(string: args[i + 1]) { return url }
        #endif
        return UpdateFeed.latestURL
    }

    /// Starts or stops the daily check as the setting changes.
    private func observe() {
        let on = withObservationTracking { preferences.checkForUpdates } onChange: {
            Task { @MainActor [weak self] in self?.observe() }
        }
        timer?.invalidate()
        timer = nil
        guard on, Self.current != nil else { return }
        let first = Timer(timeInterval: 60, repeats: false) { _ in Task { @MainActor [weak self] in self?.scheduled() } }
        RunLoop.main.add(first, forMode: .common)
        timer = first
    }

    private func scheduled() {
        check()
        let daily = Timer(timeInterval: 86_400, repeats: true) { _ in Task { @MainActor [weak self] in self?.check() } }
        daily.tolerance = 3_600
        RunLoop.main.add(daily, forMode: .common)
        timer = daily
    }

    func check() { check(thenInstall: false) }

    private func check(thenInstall: Bool) {
        if case .checking = state { return }
        if case .installing = state { return }
        state = .checking
        Task {
            do {
                var request = URLRequest(url: Self.feedURL, timeoutInterval: 20)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                // 404: no release published yet.
                guard status == 200 || status == 404 else { throw UpdateError.server(status) }
                let release = status == 200 ? UpdateFeed.release(fromGitHub: data, allowHTTP: Self.feedURL != UpdateFeed.latestURL) : nil
                if let current = Self.current, let newer = UpdateFeed.newer(release, than: current) {
                    offered = newer
                    if case .ready(let ready) = state, ready.version == newer.version { return }
                    state = .available(newer)
                    if thenInstall { install() } else if preferences.installUpdatesAutomatically { stage(newer) }
                } else {
                    offered = nil
                    state = .upToDate(Date())
                }
            } catch {
                state = .failed("Couldn't check for updates (\(Self.describe(error))).")
            }
        }
    }

    /// Downloads and verifies a release without touching the running app. Quiet: if anything fails the
    /// release stays on offer for a click.
    private func stage(_ release: UpdateRelease) {
        Task {
            guard let app = try? await Self.fetch(release) else { return }
            guard case .available(let current) = state, current.version == release.version else { return }
            staged = (release, app)
            state = .ready(release)
        }
    }

    private static func fetch(_ release: UpdateRelease) async throws -> URL {
        try preflight(current: Bundle.main.bundleURL)
        let zip = try await download(release.zip)
        let signature = String(decoding: try await download(release.signature), as: UTF8.self)
        guard UpdateFeed.verify(zip, signature: signature) else { throw UpdateError.badSignature }
        return try unpack(zip, expecting: release.version)
    }

    /// Swaps in the staged update as OpusBar quits, without opening it again: the next launch is the new one.
    func applyOnQuit() {
        guard preferences.installUpdatesAutomatically, case .ready = state, let staged,
              FileManager.default.fileExists(atPath: staged.app.path) else { return }
        try? swap(staged, reopen: false)
    }

    /// Verifies (if not already staged), swaps in the offered release, then relaunches.
    func install() {
        guard let release = offered else { return }
        if case .installing = state { return }
        state = .installing(release)
        Task {
            do {
                if let staged, staged.release.version == release.version, FileManager.default.fileExists(atPath: staged.app.path) {
                    try swap(staged, reopen: true)
                    return
                }
                let newApp = try await Self.fetch(release)
                try swap((release, newApp), reopen: true)
            } catch {
                state = .failed("The update didn't install (\(Self.describe(error))). Nothing was changed.")
            }
        }
    }

    /// Keeps what the card after the update will say, then hands over to the swap script.
    private func swap(_ update: (release: UpdateRelease, app: URL), reopen: Bool) throws {
        guard !swapStarted else { return }
        let note = WhatsNew(version: update.release.version.description,
                            highlights: ReleaseNotes.highlights(from: update.release.notes))
        try Self.relaunch(replacing: Bundle.main.bundleURL, with: update.app, reopen: reopen) { [preferences] in
            preferences.whatsNew = note
        }
        swapStarted = true
    }

    func openReleasePage() {
        NSWorkspace.shared.open(offered?.page ?? URL(string: "https://github.com/\(UpdateFeed.repository)/releases")!)
    }

    /// A past release's page, for "Full notes" on the card after an update.
    func openReleasePage(version: String) {
        NSWorkspace.shared.open(URL(string: "https://github.com/\(UpdateFeed.repository)/releases/tag/v\(version)")!)
    }

    // MARK: Steps

    enum UpdateError: Error {
        case server(Int)
        case badSignature
        case notAnUpdate(String)
        case notWritable
        case translocated
    }

    private static var userAgent: String { "OpusBar/\(current?.description ?? "dev")" }

    private static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.server(status) }
        return data
    }

    /// Unzips into a fresh temporary folder and checks the app inside is OpusBar at the promised version.
    private static func unpack(_ zip: Data, expecting version: AppVersion) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "OpusBar-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let archive = folder.appending(path: "update.zip")
        try zip.write(to: archive)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, folder.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw UpdateError.notAnUpdate("the zip didn't open") }
        let app = folder.appending(path: "OpusBar.app")
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let shipped = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
              shipped == version
        else { throw UpdateError.notAnUpdate("the zip doesn't hold OpusBar \(version)") }
        return app
    }

    /// A small shell step waits for this process to quit, moves the old app aside, moves the new one in
    /// and opens it; if the move fails, it puts the old app back and opens that.
    /// The app can be replaced where it runs: not a read-only copy macOS made for a download, and a writable folder.
    private static func preflight(current: URL) throws {
        // Opened straight from a download (DMG or Downloads): macOS runs a read-only copy elsewhere.
        guard !current.path.contains("/AppTranslocation/") else { throw UpdateError.translocated }
        guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else { throw UpdateError.notWritable }
    }

    private static func relaunch(replacing current: URL, with new: URL, reopen: Bool, beforeStart: () -> Void) throws {
        try preflight(current: current)
        let aside = new.deletingLastPathComponent().appending(path: "OpusBar-previous.app")
        // DEBUG: the relaunched app keeps a test HOME (LaunchServices starts it with a fresh environment).
        var open = reopen ? "/usr/bin/open" : ":"
        #if DEBUG
        if reopen, let home = ProcessInfo.processInfo.environment["HOME"] {
            open += " --env HOME=\"\(home)\""
        }
        #endif
        let script = """
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        if /bin/mv "$2" "$4" && /bin/mv "$3" "$2"; then \(open) "$2"; else
          [ -e "$2" ] || /bin/mv "$4" "$2"; \(open) "$2"; fi
        """
        let step = Process()
        step.executableURL = URL(fileURLWithPath: "/bin/sh")
        step.arguments = ["-c", script, "opusbar-update", String(ProcessInfo.processInfo.processIdentifier),
                          current.path, new.path, aside.path]
        try step.run()
        beforeStart()
        if reopen { NSApp.terminate(nil) }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case UpdateError.server(let status): "GitHub answered \(status)"
        case UpdateError.badSignature: "the download's signature didn't match"
        case UpdateError.notAnUpdate(let reason): reason
        case UpdateError.notWritable: "OpusBar's folder can't be written; download it from GitHub instead"
        case UpdateError.translocated: "OpusBar is running from the download; move it to Applications, open it again, then update"
        case let error as URLError where error.code == .notConnectedToInternet: "no internet connection"
        default: error.localizedDescription
        }
    }
}
