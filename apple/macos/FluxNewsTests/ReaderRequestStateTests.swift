import XCTest

final class ReaderRequestStateTests: XCTestCase {
    func testLatestReaderRequestWins() {
        var state = ReaderRequestState()
        let first = state.begin()
        let second = state.begin()

        XCTAssertFalse(state.isCurrent(first))
        XCTAssertTrue(state.isCurrent(second))
    }
}
