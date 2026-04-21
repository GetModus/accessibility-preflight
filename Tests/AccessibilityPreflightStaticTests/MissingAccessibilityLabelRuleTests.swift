import XCTest
@testable import AccessibilityPreflightStatic

final class MissingAccessibilityLabelRuleTests: XCTestCase {
    func testFlagsImageOnlyButtonWithoutAccessibilityLabel() {
        let source = "Button(action: save) { Image(systemName: \"square.and.arrow.down\") }"
        let findings = MissingAccessibilityLabelRule().scan(path: "SaveView.swift", source: source)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.severity.rawValue, "WARN")
    }
}
