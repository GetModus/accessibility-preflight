import XCTest
@testable import AccessibilityPreflightCore

final class PackageSmokeTests: XCTestCase {
    func testSeverityOrderingPlacesCriticalAboveWarn() {
        XCTAssertGreaterThan(Severity.critical.sortRank, Severity.warn.sortRank)
    }
}
