import Foundation

public struct Report: Codable, Equatable {
    public let findings: [Finding]
    public let assistedChecks: [String]

    public init(findings: [Finding], assistedChecks: [String]) {
        self.findings = findings
        self.assistedChecks = assistedChecks
    }

    private enum CodingKeys: String, CodingKey {
        case findings
        case assistedChecks = "assisted_checks"
    }
}
