import XCTest
@testable import AccessibilityPreflightStatic

final class GenericAccessibilityLabelRuleTests: XCTestCase {
    func testFlagsGenericAccessibilityLabelText() {
        let source = ".accessibilityLabel(\"Button\")"
        let findings = GenericAccessibilityLabelRule().scan(path: "SaveView.swift", source: source)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.title, "Generic accessibility label")
    }
}
