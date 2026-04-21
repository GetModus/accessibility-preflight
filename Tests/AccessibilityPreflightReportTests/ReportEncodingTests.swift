import XCTest
@testable import AccessibilityPreflightReport
import AccessibilityPreflightCore

final class ReportEncodingTests: XCTestCase {
    func testReportEncodesSeverityAndConfidence() throws {
        let finding = Finding(
            platform: "ios",
            surface: "voiceover",
            severity: .critical,
            confidence: .proven,
            title: "Missing label",
            detail: "Runtime element had empty label",
            fix: "Set accessibilityLabel",
            evidence: ["label=''"],
            file: "WelcomeView.swift",
            line: 42,
            verifiedBy: "runtime"
        )

        let report = Report(findings: [finding], assistedChecks: [])
        let data = try JSONReportWriter.write(report)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let findings = try XCTUnwrap(object["findings"] as? [[String: Any]])
        let encodedFinding = try XCTUnwrap(findings.first)

        XCTAssertEqual(encodedFinding["severity"] as? String, "CRITICAL")
        XCTAssertEqual(encodedFinding["confidence"] as? String, "proven")
    }
}
