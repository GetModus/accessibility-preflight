import Foundation
import AccessibilityPreflightCore
import AccessibilityPreflightReport
import AccessibilityPreflightStatic
import AccessibilityPreflightBuild
import AccessibilityPreflightIOSRuntime
import AccessibilityPreflightMacRuntime

struct CLIOptions {
    var command: CLICommand = .preflight
    var path: String = "."
    var json = false
    var reportInput: String?
    var checklistPlatform: String?
    var artifactPath: String?
    var branchName: String?
}

struct CLIExecutionResult {
    let output: String
    let exitCode: Int
}

func parseArguments(_ arguments: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var positionals: [String] = []
    var iterator = arguments.makeIterator()

    if arguments.isEmpty {
        return options
    }

    while let argument = iterator.next() {
        switch argument {
        case "--help", "-h":
            options.command = .help
        case "--json":
            options.json = true
        case "--path", "-p":
            guard let value = iterator.next() else {
                throw CLIError.missingValue(flag: argument)
            }
            options.path = value
        case "--input":
            guard let value = iterator.next() else {
                throw CLIError.missingValue(flag: argument)
            }
            options.reportInput = value
        case "--platform":
            guard let value = iterator.next() else {
                throw CLIError.missingValue(flag: argument)
            }
            options.checklistPlatform = value
        case "--artifact":
            guard let value = iterator.next() else {
                throw CLIError.missingValue(flag: argument)
            }
            options.artifactPath = value
        case "--branch":
            guard let value = iterator.next() else {
                throw CLIError.missingValue(flag: argument)
            }
            options.branchName = value
        case let value where value.hasPrefix("-"):
            throw CLIError.unsupportedFlag(value)
        default:
            positionals.append(argument)
        }
    }

    if let first = positionals.first {
        if let command = CLICommand(argument: first) {
            options.command = command
            if positionals.count > 1 {
                switch command {
                case .report:
                    options.reportInput = positionals[1]
                case .checklists:
                    options.checklistPlatform = positionals[1]
                case .applyArtifact:
                    options.artifactPath = positionals[1]
                default:
                    options.path = positionals[1]
                }
            }
        } else {
            options.path = first
        }
    }

    return options
}

func executeCLI(arguments: [String], dependencies: PreflightDependencies = makeLiveDependencies()) async throws -> CLIExecutionResult {
    let options = try parseArguments(arguments)

    switch options.command {
    case .preflight, .static, .iosRun, .macosRun:
        let runner = PreflightRunner(dependencies: dependencies)
        let result = try await runner.run(path: options.path, command: options.command)
        let report = try makeAugmentedReport(from: result)
        return CLIExecutionResult(
            output: try TerminalRenderer.render(report, format: options.json ? .json : .terminal),
            exitCode: report.findings.contains(where: { $0.severity == .critical }) ? 1 : 0
        )
    case .report:
        let report = try loadReport(from: options)
        return CLIExecutionResult(
            output: try TerminalRenderer.render(report, format: options.json ? .json : .terminal),
            exitCode: report.findings.contains(where: { $0.severity == .critical }) ? 1 : 0
        )
    case .checklists:
        let platform = try checklistPlatform(from: options)
        return CLIExecutionResult(
            output: options.json ? try renderChecklistJSON(for: platform) : renderChecklist(for: platform),
            exitCode: 0
        )
    case .manualWorkflows:
        let platform = try checklistPlatform(from: options)
        return CLIExecutionResult(
            output: options.json ? try renderManualWorkflowJSON(for: platform) : renderManualWorkflow(for: platform),
            exitCode: 0
        )
    case .applyArtifact:
        let artifactPath = try remediationArtifactPath(from: options)
        let branchName = try remediationBranchName(from: options)
        let summary = try RemediationArtifactApplier(
            artifactPath: artifactPath,
            branchName: branchName
        ).apply()
        return CLIExecutionResult(output: summary, exitCode: 0)
    case .help:
        return CLIExecutionResult(output: renderUsage(), exitCode: 0)
    }
}

func makeLiveDependencies() -> PreflightDependencies {
    let staticScanner = StaticScanner()
    let iosVerifier = IOSRuntimeVerifier()
    let macVerifier = MacRuntimeVerifier()

    return PreflightDependencies(
        staticScan: { project in
            let findings = try scanStaticSources(at: project.rootPath, using: staticScanner)
            return PreflightSliceResult(
                findings: findings,
                assistedChecks: [
                    "Scanned \(findings.count) static accessibility finding(s) across Swift sources."
                ]
            )
        },
        iosRuntime: { project in
            let runtimeResult = try await iosVerifier.verify(projectRoot: project.rootPath, simulatorID: "booted")
            return runtimeSliceResult(from: runtimeResult)
        },
        macRuntime: { project in
            let runtimeResult = try await macVerifier.verify(
                projectRoot: project.rootPath,
                appName: XcodeProjectLocator.defaultSchemeName(for: project.projectName)
            )
            return runtimeSliceResult(from: runtimeResult)
        }
    )
}

func runtimeSliceResult(from runtimeResult: RuntimeVerificationResult) -> PreflightSliceResult {
    let artifactChecks = runtimeResult.artifacts.map { "Runtime artifact: \($0)" }
    return PreflightSliceResult(
        findings: runtimeResult.findings,
        assistedChecks: runtimeResult.assistedChecks + artifactChecks
    )
}

func scanStaticSources(at rootPath: String, using scanner: StaticScanner) throws -> [Finding] {
    let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
    let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )

    let swiftFiles = try enumerator?.compactMap { element -> URL? in
        guard let url = element as? URL, url.pathExtension == "swift" else {
            return nil
        }
        let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
        return resourceValues.isRegularFile == true ? url : nil
    } ?? []

    var findings: [Finding] = []
    for url in swiftFiles {
        let source = try String(contentsOf: url, encoding: .utf8)
        findings.append(contentsOf: scanner.scan(path: url.path, source: source))
    }

    return findings
}

func makeReport(from result: PreflightRunResult) -> Report {
    Report(findings: result.findings, assistedChecks: result.assistedChecks)
}

func makeAugmentedReport(from result: PreflightRunResult) throws -> Report {
    let report = makeReport(from: result)
    guard report.findings.contains(where: { $0.severity == .warn || $0.severity == .critical }) else {
        return report
    }

    let artifactPath = try RemediationArtifact(project: result.project, report: report).generate()
    return Report(
        findings: report.findings,
        assistedChecks: report.assistedChecks + ["Review the generated remediation artifact at \(artifactPath)"]
    )
}

private enum CLIError: LocalizedError {
    case missingValue(flag: String)
    case unsupportedFlag(String)
    case missingReportInput
    case missingChecklistPlatform
    case invalidPlatform(String)
    case missingArtifactPath
    case missingBranchName

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .unsupportedFlag(let flag):
            return "Unsupported flag \(flag)"
        case .missingReportInput:
            return "Report command requires --input <report.json>"
        case .missingChecklistPlatform:
            return "Checklists command requires --platform ios|macos"
        case .invalidPlatform(let platform):
            return "Unsupported platform \(platform). Use ios or macos."
        case .missingArtifactPath:
            return "Apply-artifact requires --artifact <artifact-directory>"
        case .missingBranchName:
            return "Apply-artifact requires --branch <branch-name>"
        }
    }
}

private func loadReport(from options: CLIOptions) throws -> Report {
    guard let inputPath = options.reportInput else {
        throw CLIError.missingReportInput
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
    return try JSONDecoder().decode(Report.self, from: data)
}

private func checklistPlatform(from options: CLIOptions) throws -> String {
    guard let platform = options.checklistPlatform else {
        throw CLIError.missingChecklistPlatform
    }

    switch platform.lowercased() {
    case "ios":
        return "ios"
    case "macos", "mac":
        return "macos"
    default:
        throw CLIError.invalidPlatform(platform)
    }
}

private func remediationArtifactPath(from options: CLIOptions) throws -> String {
    guard let artifactPath = options.artifactPath else {
        throw CLIError.missingArtifactPath
    }

    return artifactPath
}

private func remediationBranchName(from options: CLIOptions) throws -> String {
    guard let branchName = options.branchName else {
        throw CLIError.missingBranchName
    }

    return branchName
}

private func renderChecklist(for platform: String) -> String {
    let title = platform == "macos" ? "Accessibility Audit Checklist (macOS)" : "Accessibility Audit Checklist (iOS)"
    let lines = checklistItems(for: platform).map { "- \($0)" }

    return ([title] + lines).joined(separator: "\n")
}

private func renderChecklistJSON(for platform: String) throws -> String {
    let payload = ChecklistPayload(platform: platform, items: checklistItems(for: platform))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(decoding: try encoder.encode(payload), as: UTF8.self)
}

private func renderManualWorkflow(for platform: String) -> String {
    let workflow = manualWorkflow(for: platform)
    let sections = workflow.sections.map { section in
        let items = section.steps.map { "- \($0)" }.joined(separator: "\n")
        return "\(section.title)\n\(items)"
    }

    return ([
        workflow.title,
        workflow.summary
    ] + sections).joined(separator: "\n\n")
}

private func renderManualWorkflowJSON(for platform: String) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(decoding: try encoder.encode(manualWorkflow(for: platform)), as: UTF8.self)
}

private func renderUsage() -> String {
    """
    Accessibility Preflight

    Usage:
      accessibility-preflight preflight [PATH] [--json]
      accessibility-preflight static [PATH] [--json]
      accessibility-preflight ios-run [PATH] [--json]
      accessibility-preflight macos-run [PATH] [--json]
      accessibility-preflight report --input REPORT.json [--json]
      accessibility-preflight checklists --platform ios|macos [--json]
      accessibility-preflight manual-workflows --platform ios|macos [--json]
      accessibility-preflight apply-artifact --artifact ARTIFACT_DIR --branch BRANCH_NAME
      accessibility-preflight help

    Commands:
      preflight         Run static checks plus the default runtime lane for the discovered Apple target.
      static            Run source-level accessibility checks only.
      ios-run           Run the iOS runtime verifier only.
      macos-run         Run the macOS runtime verifier only.
      report            Re-render an existing JSON report.
      checklists        Print the short assisted-verification checklist for iOS or macOS.
      manual-workflows  Print the fuller manual assistive-tech workflow for iOS or macOS.
      apply-artifact    Apply a generated remediation artifact on a review branch.
      help              Show this help text.

    Notes:
      - The tool is proposal-first: preflight generates review artifacts instead of silently rewriting app code.
      - iOS is the primary lane today. macOS support is build-and-launch proof plus assisted verification.
      - Use --json on any reporting command when you want machine-readable output.
    """
}

private func checklistItems(for platform: String) -> [String] {
    switch platform {
    case "macos":
        return [
            "Verify keyboard-only reachability across the main window, toolbar, sidebar, and dialogs.",
            "Confirm VoiceOver announces actionable controls with distinct names and correct roles.",
            "Inspect the live accessibility hierarchy for modal focus containment and escape behavior.",
            "Check repeated controls for naming collisions that break Voice Control targeting.",
            "Review reduced motion, reduced transparency, and high-contrast affordances where applicable."
        ]
    default:
        return [
            "Verify VoiceOver focus order and announcements on each audited screen.",
            "Confirm Voice Control can uniquely target visible primary actions.",
            "Run the largest Dynamic Type category and inspect for clipping, truncation, and overlap.",
            "Check modal presentation flows for trapped focus or missing dismissal affordances.",
            "Review reduced motion and contrast-sensitive UI for accessibility regressions."
        ]
    }
}

private struct ChecklistPayload: Codable {
    let platform: String
    let items: [String]
}

private struct ManualWorkflow: Codable {
    let platform: String
    let title: String
    let summary: String
    let sections: [ManualWorkflowSection]
}

private struct ManualWorkflowSection: Codable {
    let title: String
    let steps: [String]
}

private func manualWorkflow(for platform: String) -> ManualWorkflow {
    switch platform {
    case "macos":
        return ManualWorkflow(
            platform: platform,
            title: "Manual Assistive-Tech Workflow (macOS)",
            summary: "Use this after the automated pass to confirm keyboard access, VoiceOver behavior, and window-level accessibility on the built Mac app.",
            sections: [
                ManualWorkflowSection(
                    title: "Keyboard",
                    steps: [
                        "Navigate the primary window, toolbar, sidebar, and dialogs without a pointer.",
                        "Confirm the first responder is visible and escape or cancel paths work consistently.",
                        "Check modal containment so focus cannot fall behind active sheets or popovers."
                    ]
                ),
                ManualWorkflowSection(
                    title: "VoiceOver",
                    steps: [
                        "Walk the primary window in reading order and confirm controls announce distinct names and roles.",
                        "Open the rotor and confirm landmarks, headings, and controls feel intentional rather than noisy.",
                        "Verify tables, outlines, and split views expose structure clearly."
                    ]
                ),
                ManualWorkflowSection(
                    title: "Display Accommodations",
                    steps: [
                        "Check reduced transparency, increased contrast, and reduced motion settings when the app uses materials or animated transitions.",
                        "Review hover, selection, and focus affordances in both light and dark appearances."
                    ]
                )
            ]
        )
    default:
        return ManualWorkflow(
            platform: platform,
            title: "Manual Assistive-Tech Workflow (iOS)",
            summary: "Use this after the automated pass to confirm VoiceOver, Voice Control, and Dynamic Type behavior on the audited iPhone build.",
            sections: [
                ManualWorkflowSection(
                    title: "VoiceOver",
                    steps: [
                        "Move through each audited screen in swipe order and confirm names, values, hints, and traits are correct.",
                        "Check modal screens and sheets for obvious entry, containment, and dismissal behavior.",
                        "Confirm repeated actions still sound distinct enough to understand in context."
                    ]
                ),
                ManualWorkflowSection(
                    title: "Voice Control",
                    steps: [
                        "Speak the visible primary actions exactly as rendered and confirm each one can be targeted uniquely.",
                        "Look for duplicate visible labels that make command phrases ambiguous.",
                        "Check overlays, sheets, and destructive actions for dependable spoken targeting."
                    ]
                ),
                ManualWorkflowSection(
                    title: "Dynamic Type",
                    steps: [
                        "Run the largest accessibility text size and inspect for clipping, truncation, overlap, and off-screen primary actions.",
                        "Confirm scroll containers still expose critical content above the fold or with obvious access paths.",
                        "Review onboarding, empty states, and paywalls because they often compress first."
                    ]
                )
            ]
        )
    }
}
