import Foundation

public enum CLICommand: String, CaseIterable, Equatable, Sendable {
    case preflight
    case `static`
    case iosRun = "ios-run"
    case macosRun = "macos-run"
    case applyArtifact = "apply-artifact"
    case report
    case checklists
    case manualWorkflows = "manual-workflows"
    case help

    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}

public struct Finding: Codable, Equatable {
    public let platform: String
    public let surface: String
    public let severity: Severity
    public let confidence: Confidence
    public let title: String
    public let detail: String
    public let fix: String
    public let evidence: [String]
    public let file: String?
    public let line: Int?
    public let verifiedBy: String

    public init(
        platform: String,
        surface: String,
        severity: Severity,
        confidence: Confidence,
        title: String,
        detail: String,
        fix: String,
        evidence: [String],
        file: String?,
        line: Int?,
        verifiedBy: String
    ) {
        self.platform = platform
        self.surface = surface
        self.severity = severity
        self.confidence = confidence
        self.title = title
        self.detail = detail
        self.fix = fix
        self.evidence = evidence
        self.file = file
        self.line = line
        self.verifiedBy = verifiedBy
    }

    private enum CodingKeys: String, CodingKey {
        case platform
        case surface
        case severity
        case confidence
        case title
        case detail
        case fix
        case evidence
        case file
        case line
        case verifiedBy = "verified_by"
    }
}

public struct PreflightSliceResult: Equatable {
    public let findings: [Finding]
    public let assistedChecks: [String]

    public init(findings: [Finding], assistedChecks: [String]) {
        self.findings = findings
        self.assistedChecks = assistedChecks
    }
}

public struct PreflightRunResult: Equatable {
    public let project: DiscoveredProject
    public let findings: [Finding]
    public let assistedChecks: [String]

    public init(project: DiscoveredProject, findings: [Finding], assistedChecks: [String]) {
        self.project = project
        self.findings = findings
        self.assistedChecks = assistedChecks
    }
}

public struct PreflightDependencies {
    public let staticScan: (DiscoveredProject) async throws -> PreflightSliceResult
    public let iosRuntime: (DiscoveredProject) async throws -> PreflightSliceResult
    public let macRuntime: (DiscoveredProject) async throws -> PreflightSliceResult

    public init(
        staticScan: @escaping (DiscoveredProject) async throws -> PreflightSliceResult,
        iosRuntime: @escaping (DiscoveredProject) async throws -> PreflightSliceResult,
        macRuntime: @escaping (DiscoveredProject) async throws -> PreflightSliceResult
    ) {
        self.staticScan = staticScan
        self.iosRuntime = iosRuntime
        self.macRuntime = macRuntime
    }
}

public struct PreflightRunner {
    private let dependencies: PreflightDependencies

    public init(dependencies: PreflightDependencies) {
        self.dependencies = dependencies
    }

    public func run(path: String, command: CLICommand) async throws -> PreflightRunResult {
        let project = try ProjectDiscovery.discover(in: path)
        let staticResult: PreflightSliceResult
        let runtimeResult: PreflightSliceResult?

        switch command {
        case .static:
            staticResult = try await dependencies.staticScan(project)
            runtimeResult = nil
        case .iosRun:
            staticResult = PreflightSliceResult(findings: [], assistedChecks: [])
            runtimeResult = try await dependencies.iosRuntime(project)
        case .macosRun:
            staticResult = PreflightSliceResult(findings: [], assistedChecks: [])
            runtimeResult = try await dependencies.macRuntime(project)
        case .preflight:
            staticResult = try await dependencies.staticScan(project)
            switch project.platform {
            case "macos":
                runtimeResult = try await dependencies.macRuntime(project)
            default:
                runtimeResult = try await dependencies.iosRuntime(project)
            }
        case .report, .checklists, .manualWorkflows, .applyArtifact, .help:
            throw PreflightRunnerError.unsupportedCommand(command)
        }

        let findings = staticResult.findings + (runtimeResult?.findings ?? [])
        let assistedChecks = staticResult.assistedChecks + (runtimeResult?.assistedChecks ?? [])

        return PreflightRunResult(
            project: project,
            findings: findings,
            assistedChecks: assistedChecks
        )
    }
}

public enum PreflightRunnerError: LocalizedError, Equatable {
    case unsupportedCommand(CLICommand)

    public var errorDescription: String? {
        switch self {
        case .unsupportedCommand(let command):
            return "Unsupported preflight runner command: \(command.rawValue)"
        }
    }
}
