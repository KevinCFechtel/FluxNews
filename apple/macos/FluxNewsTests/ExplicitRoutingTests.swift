import XCTest

final class ExplicitRoutingTests: XCTestCase {
    func testExplicitRoutePreventsSavedStartupScopeFromApplying() {
        var routeState = StartupRouteState()

        XCTAssertTrue(routeState.shouldApplyStartupScope)

        routeState.markExplicitRoute()

        XCTAssertFalse(routeState.shouldApplyStartupScope)
    }
}
