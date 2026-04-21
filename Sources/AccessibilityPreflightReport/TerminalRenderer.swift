import Foundation

public enum TerminalRenderer {
    public enum OutputFormat {
        case terminal
        case json
    }

    public static func render(_ report: Report, format: OutputFormat = .terminal) throws -> String {
        switch format {
        case .terminal:
            return renderTerminal(report)
        case .json:
            return try renderJSON(report)
        }
    }

    public static func renderJSON(_ report: Report) throws -> String {
        String(decoding: try JSONReportWriter.write(report), as: UTF8.self)
    }

    private static func renderTerminal(_ report: Report) -> String {
        let criticalCount = report.findings.filter { $0.severity == .critical }.count
        let warnCount = report.findings.filter { $0.severity == .warn }.count
        let infoCount = report.findings.filter { $0.severity == .info }.count

        return [
            "Accessibility Preflight Report",
            "Critical: \(criticalCount)  Warn: \(warnCount)  Info: \(infoCount)",
            "Assisted checks: \(report.assistedChecks.count)"
        ].joined(separator: "\n")
    }
}
