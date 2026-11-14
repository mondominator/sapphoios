import XCTest
@testable import Sappho

/// List screens reload every time they reappear. Only the first load may
/// cover the list with a spinner or an error; otherwise coming back from a
/// detail screen rebuilt the list and lost its scroll position.
final class ListLoadStateTests: XCTestCase {
    func testFirstLoadShowsSpinnerThenList() {
        var state = ListLoadState()
        XCTAssertTrue(state.showsSpinner, "nothing to show before the first load")
        state.begin()
        XCTAssertTrue(state.showsSpinner)
        state.end()
        XCTAssertFalse(state.showsSpinner)
        XCTAssertNil(state.blockingError)
    }

    func testReloadAfterSuccessKeepsTheList() {
        var state = ListLoadState()
        state.begin(); state.end()

        state.begin()
        XCTAssertFalse(state.showsSpinner, "a reload must not replace the list with a spinner")
        state.end()
        XCTAssertFalse(state.showsSpinner)
    }

    func testFailedReloadKeepsTheList() {
        var state = ListLoadState()
        state.begin(); state.end()

        state.begin()
        state.failed("offline")
        state.end()
        XCTAssertNil(state.blockingError, "a failed reload must not replace the loaded list")
        XCTAssertFalse(state.showsSpinner)
    }

    func testFailedFirstLoadShowsErrorAndRetryShowsSpinner() {
        var state = ListLoadState()
        state.begin()
        state.failed("offline")
        state.end()
        XCTAssertEqual(state.blockingError, "offline")

        state.begin()
        XCTAssertNil(state.blockingError)
        XCTAssertTrue(state.showsSpinner)
        state.end()
        XCTAssertFalse(state.showsSpinner)
        XCTAssertNil(state.blockingError)
    }
}
