import XCTest
@testable import AccessibilityPreflightStatic

final class FixedTypeSizeRuleTests: XCTestCase {
    func testFlagsFixedPointSizeFontUsage() {
        let source = ".font(.system(size: 17))"
        let findings = FixedTypeSizeRule().scan(path: "TitleView.swift", source: source)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.severity.rawValue, "WARN")
    }

    func testFlagsFixedCustomFontWithoutRelativeTextStyle() {
        let source = #".font(.custom("Inter", size: 17))"#

        let findings = StaticScanner().scan(path: "TitleView.swift", source: source)

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.title, "Fixed custom font point size")
    }

    func testDoesNotFlagCustomFontWhenRelativeTextStyleIsPresent() {
        let source = #".font(.custom("Inter", size: 17, relativeTo: .body))"#

        let findings = StaticScanner().scan(path: "TitleView.swift", source: source)

        XCTAssertTrue(findings.isEmpty)
    }
}
