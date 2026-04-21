import XCTest

private struct AuditIssueRecord: Codable {
    let auditType: String
    let compactDescription: String
    let detailedDescription: String
    let elementDescription: String?
    let elementIdentifier: String?
    let elementLabel: String?
    let elementType: String?
}

private struct AuditReport: Codable {
    let bundleIdentifier: String
    let issues: [AuditIssueRecord]

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "bundle_identifier"
        case issues
    }
}

@MainActor
final class AccessibilityAuditHarnessUITests: XCTestCase {
    func testAccessibilityAudit() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: AuditRunConfiguration.activationTimeout),
            "Target app did not reach the foreground before the accessibility audit ran."
        )

        var issues: [AuditIssueRecord] = []
        try app.performAccessibilityAudit { issue in
            issues.append(
                AuditIssueRecord(
                    auditType: Self.auditTypeName(issue.auditType),
                    compactDescription: issue.compactDescription,
                    detailedDescription: issue.detailedDescription,
                    elementDescription: issue.element?.description,
                    elementIdentifier: issue.element?.identifier,
                    elementLabel: issue.element?.label,
                    elementType: issue.element.map { String(describing: $0.elementType) }
                )
            )
            return true
        }

        try writeReport(
            AuditReport(
                bundleIdentifier: AuditRunConfiguration.targetBundleIdentifier,
                issues: issues
            )
        )
    }

    private func writeReport(_ report: AuditReport) throws {
        let reportURL = URL(fileURLWithPath: AuditRunConfiguration.reportPath)
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: reportURL)
    }

    private static func auditTypeName(_ auditType: XCUIAccessibilityAuditType) -> String {
        switch auditType {
        case .contrast:
            return "contrast"
        case .elementDetection:
            return "elementDetection"
        case .hitRegion:
            return "hitRegion"
        case .sufficientElementDescription:
            return "sufficientElementDescription"
        case .dynamicType:
            return "dynamicType"
        case .textClipped:
            return "textClipped"
        case .trait:
            return "trait"
        default:
            return "unknown"
        }
    }
}
