public struct RuntimeVerificationResult {
    public let findings: [Finding]
    public let assistedChecks: [String]
    public let artifacts: [String]

    public init(findings: [Finding], assistedChecks: [String], artifacts: [String] = []) {
        self.findings = findings
        self.assistedChecks = assistedChecks
        self.artifacts = artifacts
    }
}
