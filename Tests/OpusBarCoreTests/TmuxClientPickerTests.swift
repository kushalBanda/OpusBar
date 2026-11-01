@testable import OpusBarCore
import XCTest

final class TmuxClientPickerTests: XCTestCase {
    /// Captured from tmux 3.6a with `TmuxClientPicker.panesFormat` and `clientsFormat`.
    private let panes = "/dev/ttys000\t%0\talpha\n/dev/ttys002\t%1\talpha\n/dev/ttys004\t%2\tbeta\n"
    private let clients = "/dev/ttys005\t62041\talpha\t1793469262\n"

    func testFindsTheClientOnThePanesSession() {
        XCTAssertEqual(TmuxClientPicker.pick(paneTty: "ttys002", panes: panes, clients: clients),
                       .init(paneId: "%1", clientTty: "/dev/ttys005", clientPid: 62041))
    }

    func testIgnoresMalformedLines() {
        let bad = "garbage\n/dev/ttys000\t0\talpha\n;rm\t%0\talpha\n/dev/ttys000\tx\talpha\n"
        XCTAssertNil(TmuxClientPicker.pick(paneTty: "ttys000", panes: bad, clients: clients))
        let badClients = "/dev/ttys005\tnot-a-pid\talpha\t1\n--evil\t5\talpha\t1\n"
        XCTAssertNil(TmuxClientPicker.pick(paneTty: "ttys000", panes: panes, clients: badClients))
    }
}
