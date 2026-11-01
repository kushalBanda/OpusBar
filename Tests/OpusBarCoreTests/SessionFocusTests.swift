import Foundation
@testable import OpusBarCore
import OpusBarWire
import XCTest

final class SessionFocusPlannerTests: XCTestCase {
    private func session(host: SessionHost? = nil) -> Session {
        var session = Session(id: "a", cwd: "/Users/me/api-server", startedAt: Date(timeIntervalSince1970: 0))
        session.host = host
        return session
    }

    private let needles = WindowNeedles(folder: "api-server")
    private func raise(_ app: String) -> FocusStep { .raiseWindow(appPath: app, needles: needles) }

    func testNoHostPlansOpenMenuOnly() {
        XCTAssertEqual(SessionFocusPlanner.plan(session()), [.openMenu])
    }

    /// Any app OpusBar has no route for still comes forward.
    func testUnknownAppRaisesItsWindowThenActivates() {
        let terax = SessionHost(appName: "Terax", appPath: "/Applications/Terax.app", tty: "ttys004")
        XCTAssertEqual(SessionFocusPlanner.plan(session(host: terax)),
                       [raise("/Applications/Terax.app"), .activateApp(appPath: "/Applications/Terax.app")])
    }

    func testOrcaMalformedHandleIsDropped() {
        var hosted = session(host: SessionHost(appName: "Orca", appPath: "/Applications/Orca.app", tty: "ttys004"))
        hosted.term = TermInfo(orcaTerminalHandle: "--help")
        XCTAssertEqual(SessionFocusPlanner.plan(hosted).first,
                       .orcaFind(cwd: "/Users/me/api-server", agent: .claude, appPath: "/Applications/Orca.app"))
    }

    func testTerminalAppWithoutASafeTtyOnlyActivates() {
        for tty in [nil, "ttys004\"; quit"] {
            let host = SessionHost(appName: "Terminal", appPath: "/System/Applications/Utilities/Terminal.app", tty: tty)
            XCTAssertEqual(SessionFocusPlanner.plan(session(host: host)),
                           [raise("/System/Applications/Utilities/Terminal.app"),
                            .activateApp(appPath: "/System/Applications/Utilities/Terminal.app")])
        }
    }

    func testITermPlansRevealThenTab() {
        let id = "w0t1p0:6E5B2D3A-1C4F-4B7E-9A10-2F3E4D5C6B7A"
        var hosted = session(host: SessionHost(appName: "iTerm2", appPath: "/Applications/iTerm.app", tty: "ttys007"))
        hosted.term = TermInfo(termProgram: "iTerm.app", itermSessionId: id)
        XCTAssertEqual(Array(SessionFocusPlanner.plan(hosted).prefix(2)), [
            .itermReveal(sessionId: id, appPath: "/Applications/iTerm.app"),
            .scriptTab(app: .iterm, tty: "/dev/ttys007"),
        ])
    }

    /// cmux sets TERM_PROGRAM=ghostty; Ghostty's AppleScript would drive the wrong app.
    func testCmuxIsNotTakenForGhostty() {
        var hosted = session(host: SessionHost(appName: "cmux", appPath: "/Applications/cmux.app", tty: "ttys004"))
        hosted.term = TermInfo(termProgram: "ghostty")
        XCTAssertNil(KnownHost.of(hosted))
    }
}

final class FocusSequenceTests: XCTestCase {
    /// Answers each step from a table and records the order it was asked in.
    private final class FakePerformer: FocusPerforming, @unchecked Sendable {
        private let lock = NSLock()
        private let answers: [FocusStep: FocusOutcome]
        private var _asked: [FocusStep] = []
        var asked: [FocusStep] { lock.withLock { _asked } }

        private let tmux: SessionHost?
        init(_ answers: [FocusStep: FocusOutcome], tmux: SessionHost? = nil) { self.answers = answers; self.tmux = tmux }

        func tmuxHost(paneTty: String, socket: String?, serverPid: Int32?) async -> SessionHost? { tmux }

        func perform(_ step: FocusStep) async -> FocusOutcome {
            lock.withLock { _asked.append(step) }
            return answers[step] ?? .notFound
        }
    }

    private let app = FocusStep.activateApp(appPath: "/Applications/Orca.app")

    func testStopsAtTheFirstFocusedStep() async {
        let performer = FakePerformer([app: .focused, .openMenu: .focused])
        let focused = await FocusSequence.run([app, .openMenu], using: performer)
        XCTAssertEqual(focused, app)
        XCTAssertEqual(performer.asked, [app])
    }

    /// A permission refused never blocks the click.
    func testDeniedStepFallsThroughToTheNext() async {
        let performer = FakePerformer([app: .denied, .openMenu: .focused])
        let focused = await FocusSequence.run([app, .openMenu], using: performer)
        XCTAssertEqual(focused, .openMenu)
    }

    func testTmuxReplansForTheClientsTerminal() async {
        var session = Session(id: "a", cwd: "/tmp/x", startedAt: Date(timeIntervalSince1970: 0))
        session.host = SessionHost(appName: nil, appPath: nil, tty: "ttys004")
        session.term = TermInfo(termProgram: "tmux", tmux: "/tmp/tmux-501/default,9,0")
        let outer = SessionHost(appName: "Terminal", appPath: "/System/Applications/Utilities/Terminal.app", tty: "ttys005")
        let tab = FocusStep.scriptTab(app: .terminalApp, tty: "/dev/ttys005")
        let performer = FakePerformer([tab: .focused], tmux: outer)
        let focused = await FocusSequence.run(session, using: performer)
        XCTAssertEqual(focused, tab)
    }
}
