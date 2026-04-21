import Foundation
import AccessibilityPreflightBuild
import AccessibilityPreflightReport
import AccessibilityPreflightCore

public enum IOSRuntimeVerifierError: LocalizedError {
    case missingBundleIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier(let scheme):
            return "Built iOS app for scheme \(scheme) did not expose a bundle identifier."
        }
    }
}

public struct IOSRuntimeVerifier {
    private let targetResolver: (String) throws -> ResolvedBuildTarget
    private let builder: (ResolvedBuildTarget, String) throws -> BuildResult
    private let simulatorBootstrap: SimulatorBootstrap
    private let accessibilityAuditRunner: IOSAccessibilityAuditRunner
    private let dynamicTypePass: DynamicTypePass
    private let screenInspector: SimulatorScreenInspector
    private let semanticIntegrationAdvisor: (String, String, String) throws -> SemanticIntegrationAdvice
    private let semanticSnapshotReader: SemanticSnapshotReader

    public init(
        targetResolver: @escaping (String) throws -> ResolvedBuildTarget = XcodeProjectLocator.resolveBuildTarget,
        builder: @escaping (ResolvedBuildTarget, String) throws -> BuildResult = XcodeBuilder.defaultBuild,
        simulatorBootstrap: SimulatorBootstrap = .init(),
        accessibilityAuditRunner: IOSAccessibilityAuditRunner = .init(),
        dynamicTypePass: DynamicTypePass = .init(),
        screenInspector: SimulatorScreenInspector = .init(),
        semanticIntegrationAdvisor: @escaping (String, String, String) throws -> SemanticIntegrationAdvice = { projectRoot, appRoot, appSlug in
            try SemanticIntegrationAdvisor().advise(projectRoot: projectRoot, appRoot: appRoot, appSlug: appSlug)
        },
        semanticSnapshotReader: SemanticSnapshotReader = .init()
    ) {
        self.targetResolver = targetResolver
        self.builder = builder
        self.simulatorBootstrap = simulatorBootstrap
        self.accessibilityAuditRunner = accessibilityAuditRunner
        self.dynamicTypePass = dynamicTypePass
        self.screenInspector = screenInspector
        self.semanticIntegrationAdvisor = semanticIntegrationAdvisor
        self.semanticSnapshotReader = semanticSnapshotReader
    }

    public func verify(
        projectRoot: String,
        simulatorID: String,
        semanticSnapshotOverridePath: String? = nil
    ) async throws -> RuntimeVerificationResult {
        let target = try targetResolver(projectRoot)
        let device = try simulatorBootstrap.resolveDevice(simulatorID: simulatorID)
        let build = try builder(target, "platform=iOS Simulator,id=\(device.identifier)")
        guard let bundleIdentifier = build.bundleIdentifier else {
            throw IOSRuntimeVerifierError.missingBundleIdentifier(build.scheme)
        }
        let appSlug = Self.semanticAppSlug(for: target, build: build)
        let semanticAdviceResult = Result { try semanticIntegrationAdvisor(projectRoot, projectRoot, appSlug) }

        try? simulatorBootstrap.terminateApp(bundleIdentifier: bundleIdentifier, on: device)
        try? simulatorBootstrap.uninstallApp(bundleIdentifier: bundleIdentifier, on: device)
        try simulatorBootstrap.installApp(at: build.buildPath, on: device)
        let semanticSnapshotDestination = Self.semanticSnapshotDestination(
            bundleIdentifier: bundleIdentifier,
            on: device,
            requestedHostPath: semanticSnapshotOverridePath ?? Self.semanticSnapshotPath(),
            using: simulatorBootstrap
        )
        let semanticLaunchRequest = Self.semanticLaunchRequest(
            bundleIdentifier: bundleIdentifier,
            outputPath: semanticSnapshotDestination.appOutputPath
        )
        let firstLaunch = try simulatorBootstrap.launchApp(
            request: semanticLaunchRequest,
            on: device
        )
        try? simulatorBootstrap.terminateApp(bundleIdentifier: bundleIdentifier, on: device)
        let relaunch = try simulatorBootstrap.launchApp(
            request: semanticLaunchRequest,
            on: device
        )
        let defaultInspection = try? screenInspector.inspect(on: device, label: "default")

        var findings = [
            Finding(
                platform: "ios",
                surface: "runtime",
                severity: .info,
                confidence: .proven,
                title: "iOS clean-install launch sequence succeeded",
                detail: "Built \(build.scheme) for iOS Simulator, launched it from a clean install, then relaunched the same build.",
                fix: "Continue with VoiceOver, Voice Control, and Dynamic Type checks against the verified simulator build.",
                evidence: [
                    "device=\(device.name) (\(device.identifier))",
                    "bundle_id=\(bundleIdentifier)",
                    "app_path=\(build.buildPath)",
                    "scheme=\(build.scheme)",
                    "first_launch_output=\(firstLaunch.launchOutput)",
                    "relaunch_output=\(relaunch.launchOutput)"
                ] + (firstLaunch.processIdentifier.map { ["first_launch_pid=\($0)"] } ?? []) +
                    (relaunch.processIdentifier.map { ["relaunch_pid=\($0)"] } ?? []),
                file: nil,
                line: nil,
                verifiedBy: "runtime"
            )
        ]

        let accessibilityAuditResult = accessibilityAuditRunner.run(
            bundleIdentifier: bundleIdentifier,
            appPath: build.buildPath,
            launchEnvironment: semanticLaunchRequest.environment,
            containerKind: target.containerKind,
            containerName: target.containerName,
            containerPath: target.containerPath,
            projectPath: target.projectPath,
            targetName: target.buildableName.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? build.scheme,
            on: device
        )

        var dynamicTypeInspection: SimulatorScreenInspectionResult?
        let dynamicTypeAudit = dynamicTypePass.run(
            bundleIdentifier: bundleIdentifier,
            on: device,
            using: simulatorBootstrap,
            semanticOutputPath: semanticSnapshotDestination.appOutputPath
        ) {
            dynamicTypeInspection = try? screenInspector.inspect(on: device, label: "dynamic-type")
        }

        switch dynamicTypeAudit {
        case .completed(let sweep):
            findings.append(
                Finding(
                    platform: "ios",
                    surface: "dynamic_type",
                    severity: .info,
                    confidence: .proven,
                    title: "Dynamic Type accessibility launch succeeded",
                    detail: "The simulator launched \(build.scheme) at \(sweep.auditedContentSizeCategory) after verifying the clean-install sequence.",
                    fix: "Review the launched screens for clipping, truncation, overlap, and broken hierarchy at the exercised accessibility size.",
                    evidence: [
                        "device=\(sweep.launch.device.name) (\(sweep.launch.device.identifier))",
                        "bundle_id=\(bundleIdentifier)",
                        "scheme=\(build.scheme)",
                        "original_content_size=\(sweep.originalContentSizeCategory)",
                        "audited_content_size=\(sweep.auditedContentSizeCategory)",
                        "dynamic_type_launch_output=\(sweep.launch.launchOutput)"
                    ] +
                        (dynamicTypeInspection.map { ["screenshot=\($0.screenshotPath)"] } ?? []) +
                        (sweep.launch.processIdentifier.map { ["dynamic_type_launch_pid=\($0)"] } ?? []),
                    file: nil,
                    line: nil,
                    verifiedBy: "runtime"
                )
            )
            findings.append(contentsOf: makeDynamicTypeInspectionFindings(from: dynamicTypeInspection))
        case .skipped(let reason):
            findings.append(
                Finding(
                    platform: "ios",
                    surface: "dynamic_type",
                    severity: .warn,
                    confidence: .assisted,
                    title: "Dynamic Type sweep requires manual follow-up",
                    detail: "The simulator build was verified, but the automated Dynamic Type sweep could not complete.",
                    fix: "Run a manual review at accessibility-extra-extra-extra-large and confirm clipping, truncation, and overlap behavior.",
                    evidence: [
                        "device=\(device.name) (\(device.identifier))",
                        "bundle_id=\(bundleIdentifier)",
                        "scheme=\(build.scheme)",
                        "reason=\(reason)"
                    ],
                    file: nil,
                    line: nil,
                    verifiedBy: "runtime"
                )
            )
        }

        findings.append(contentsOf: makeVoiceControlFindings(from: defaultInspection))

        let refreshedSemanticSnapshotDestination = Self.semanticSnapshotDestination(
            bundleIdentifier: bundleIdentifier,
            on: device,
            requestedHostPath: semanticSnapshotDestination.hostReadPath,
            using: simulatorBootstrap
        )
        let semanticSnapshotCopySourcePaths = [
            refreshedSemanticSnapshotDestination.hostContainerPath,
            semanticSnapshotDestination.hostContainerPath
        ].compactMap { $0 }.removingDuplicates()

        var assistedChecks = [
            "Review Voice Control targeting for primary actions after the clean-install and relaunch sequence.",
            "Review VoiceOver focus order in the launched simulator build.",
            "Review onboarding, permission, and empty-state flows reached during the clean-install sequence."
        ]
        if let defaultInspection, hasUsefulReadingOrder(defaultInspection.readingOrder) {
            assistedChecks.append(
                "Compare VoiceOver focus order against this on-screen reading order: \(defaultInspection.readingOrder.joined(separator: " -> "))"
            )
        }
        assistedChecks.append(contentsOf: dynamicTypePass.assistedChecks(for: dynamicTypeAudit))
        assistedChecks.append(contentsOf: makeAccessibilityAuditAssistedChecks(from: accessibilityAuditResult))

        var artifacts: [String] = []
        artifacts.append(contentsOf: makeAccessibilityAuditArtifacts(from: accessibilityAuditResult))
        var semanticSnapshot: AppSemanticSnapshot?
        mergeSemanticEvidence(
            into: &findings,
            assistedChecks: &assistedChecks,
            artifacts: &artifacts,
            adviceResult: semanticAdviceResult,
            snapshotPath: semanticSnapshotDestination.hostReadPath,
            snapshotCopySourcePaths: semanticSnapshotCopySourcePaths,
            build: build,
            bundleIdentifier: bundleIdentifier,
            appSlug: appSlug,
            resolvedSnapshot: &semanticSnapshot
        )
        findings.append(contentsOf: makeAccessibilityAuditFindings(from: accessibilityAuditResult, semanticSnapshot: semanticSnapshot))

        if let semanticSnapshot {
            let matrixResult = runDeclaredScenarioAudits(
                declaredScenarios: semanticSnapshot.auditScenarios,
                defaultScreenID: semanticSnapshot.screenID,
                target: target,
                build: build,
                bundleIdentifier: bundleIdentifier,
                device: device,
                baseLaunchEnvironment: semanticLaunchRequest.environment,
                snapshotPath: semanticSnapshotDestination.hostReadPath,
                snapshotCopySourcePaths: semanticSnapshotCopySourcePaths
            )
            findings.append(contentsOf: matrixResult.findings)
            assistedChecks.append(contentsOf: matrixResult.assistedChecks)
            artifacts.append(contentsOf: matrixResult.artifacts)
        }

        return RuntimeVerificationResult(
            findings: findings,
            assistedChecks: assistedChecks,
            artifacts: artifacts
        )
    }

    func testingMaterializeSemanticSnapshot(
        from sourcePaths: [String],
        to destinationPath: String,
        refreshExisting: Bool = false
    ) throws {
        try materializeSemanticSnapshotIfNeeded(
            from: sourcePaths,
            to: destinationPath,
            refreshExisting: refreshExisting
        )
    }

    func testingReadScenarioSemanticSnapshot(
        at snapshotPath: String,
        snapshotCopySourcePaths: [String]
    ) -> (snapshot: AppSemanticSnapshot?, warnings: [Finding]) {
        readScenarioSemanticSnapshot(
            at: snapshotPath,
            snapshotCopySourcePaths: snapshotCopySourcePaths
        )
    }
}

private extension IOSRuntimeVerifier {
    func mergeSemanticEvidence(
        into findings: inout [Finding],
        assistedChecks: inout [String],
        artifacts: inout [String],
        adviceResult: Result<SemanticIntegrationAdvice, Error>,
        snapshotPath: String,
        snapshotCopySourcePaths: [String],
        build: BuildResult,
        bundleIdentifier: String,
        appSlug: String,
        resolvedSnapshot: inout AppSemanticSnapshot?
    ) {
        switch adviceResult {
        case .failure(let error):
            findings.append(
                Finding(
                    platform: "ios",
                    surface: "runtime",
                    severity: .warn,
                    confidence: .assisted,
                    title: "Semantic integration advice could not be generated",
                    detail: "Semantic enrichment was attempted, but the runtime audit could not generate integration guidance.",
                    fix: "Review the advisor failure and continue with the OCR/runtime findings until semantic integration can be generated.",
                    evidence: [
                        "app_slug=\(appSlug)",
                        "bundle_id=\(bundleIdentifier)",
                        "scheme=\(build.scheme)",
                        "reason=\(Self.semanticErrorDescription(error))"
                    ],
                    file: nil,
                    line: nil,
                    verifiedBy: "runtime"
                )
            )
            return
        case .success(let advice):
            switch advice.status {
            case .installed:
                do {
                    try materializeSemanticSnapshotIfNeeded(
                        from: snapshotCopySourcePaths,
                        to: snapshotPath
                    )
                    let snapshot = try semanticSnapshotReader.read(from: snapshotPath)
                    resolvedSnapshot = snapshot
                    findings.append(
                        Finding(
                            platform: "ios",
                            surface: "runtime",
                            severity: .info,
                            confidence: .proven,
                            title: "App semantic snapshot enriched runtime verification",
                            detail: "The app exported semantic screen context during the simulator run, which supplements OCR-based runtime checks.",
                            fix: "Use the exported semantic context to focus VoiceOver, Voice Control, and state-verification follow-up on the declared actions and summaries.",
                            evidence: semanticEvidence(from: snapshot, snapshotPath: snapshotPath),
                            file: nil,
                            line: nil,
                            verifiedBy: "app_semantic"
                        )
                    )
                    assistedChecks.append(contentsOf: semanticAssistedChecks(from: snapshot))
                    artifacts.append(snapshotPath)
                } catch {
                    findings.append(
                        Finding(
                            platform: "ios",
                            surface: "runtime",
                            severity: .warn,
                            confidence: .assisted,
                            title: "Semantic snapshot could not be read",
                            detail: "Semantic enrichment was enabled for this app, but the runtime audit could not read a usable snapshot. OCR/runtime fallback findings are still reported.",
                            fix: "Confirm the installed integration writes a valid snapshot to the requested output path, then rerun the audit.",
                            evidence: [
                                "app_slug=\(appSlug)",
                                "bundle_id=\(bundleIdentifier)",
                                "scheme=\(build.scheme)",
                                "snapshot_path=\(snapshotPath)",
                                "reason=\(Self.semanticErrorDescription(error))"
                            ],
                            file: nil,
                            line: nil,
                            verifiedBy: "runtime"
                        )
                    )
                }
            case .missing:
                let artifactPath = advice.artifactPath ?? "unavailable"
                findings.append(
                    Finding(
                        platform: "ios",
                        surface: "runtime",
                        severity: .warn,
                        confidence: .assisted,
                        title: "Optional app semantic integration is not installed",
                        detail: "Richer semantic checks are optional and no app code was changed automatically.",
                        fix: "Review the generated artifact and install it manually if you want app-declared semantic evidence in future runtime audits.",
                        evidence: [
                            "artifact_path=\(artifactPath)",
                            "bundle_id=\(bundleIdentifier)",
                            "scheme=\(build.scheme)",
                            "warning=\(advice.warningText)"
                        ],
                        file: nil,
                        line: nil,
                        verifiedBy: "runtime"
                    )
                )
                if let artifactPath = advice.artifactPath {
                    assistedChecks.append("Review the generated semantic integration artifact at \(artifactPath)")
                    artifacts.append(artifactPath)
                }
            }
        }
    }

    func makeVoiceControlFindings(from inspection: SimulatorScreenInspectionResult?) -> [Finding] {
        guard let inspection, !inspection.duplicateCommandNames.isEmpty else {
            return []
        }

        return [
            Finding(
                platform: "ios",
                surface: "voice_control",
                severity: .warn,
                confidence: .heuristic,
                title: "Visible command names may be ambiguous for Voice Control",
                detail: "The simulator screenshot contains repeated visible labels that may map to ambiguous Voice Control phrases.",
                fix: "Rename repeated visible actions or add clearer accessible labels so spoken commands map uniquely.",
                evidence: [
                    "duplicates=\(inspection.duplicateCommandNames.joined(separator: ", "))",
                    "screenshot=\(inspection.screenshotPath)"
                ],
                file: nil,
                line: nil,
                verifiedBy: "runtime"
            )
        ]
    }

    func makeDynamicTypeInspectionFindings(from inspection: SimulatorScreenInspectionResult?) -> [Finding] {
        guard let inspection else {
            return []
        }

        var findings: [Finding] = []

        if !inspection.truncationCandidates.isEmpty {
            findings.append(
                Finding(
                    platform: "ios",
                    surface: "dynamic_type",
                    severity: .warn,
                    confidence: .heuristic,
                    title: "Text may be truncated at accessibility Dynamic Type size",
                    detail: "OCR on the accessibility-size simulator screenshot found visible text that appears ellipsized or cut off.",
                    fix: "Review the affected screen at accessibility-extra-extra-extra-large and remove clipping or truncation in critical copy.",
                    evidence: [
                        "candidates=\(inspection.truncationCandidates.joined(separator: " | "))",
                        "screenshot=\(inspection.screenshotPath)"
                    ],
                    file: nil,
                    line: nil,
                    verifiedBy: "runtime"
                )
            )
        }

        if !inspection.crowdedTextPairs.isEmpty {
            findings.append(
                Finding(
                    platform: "ios",
                    surface: "dynamic_type",
                    severity: .warn,
                    confidence: .heuristic,
                    title: "Text regions appear crowded at accessibility Dynamic Type size",
                    detail: "OCR bounding boxes on the accessibility-size simulator screenshot overlap enough to suggest crowded or colliding content.",
                    fix: "Review the affected screen at accessibility-extra-extra-extra-large and increase layout flexibility, spacing, or wrapping behavior.",
                    evidence: [
                        "pairs=\(inspection.crowdedTextPairs.joined(separator: " | "))",
                        "screenshot=\(inspection.screenshotPath)"
                    ],
                    file: nil,
                    line: nil,
                    verifiedBy: "runtime"
                )
            )
        }

        return findings
    }

    func makeAccessibilityAuditFindings(
        from result: IOSAccessibilityAuditExecutionResult,
        semanticSnapshot: AppSemanticSnapshot?,
        summaryScope: String = "the current iOS screen"
    ) -> [Finding] {
        switch result {
        case .skipped(let reason):
            return [
                Finding(
                    platform: "ios",
                    surface: "accessibility_audit",
                    severity: .warn,
                    confidence: .assisted,
                    title: "Apple accessibility audit could not run automatically",
                    detail: "The runtime verifier launched the app successfully, but the Apple XCTest accessibility audit harness did not complete for \(summaryScope).",
                    fix: "Review the harness failure, then rerun preflight so first-party accessibility audit findings can be merged into the report.",
                    evidence: ["reason=\(reason)"],
                    file: nil,
                    line: nil,
                    verifiedBy: "apple_accessibility_audit"
                )
            ]
        case .completed(let completed):
            var findings = [
                Finding(
                    platform: "ios",
                    surface: "accessibility_audit",
                    severity: completed.issues.isEmpty ? .info : .warn,
                    confidence: .proven,
                    title: completed.issues.isEmpty
                        ? "Apple accessibility audit passed for \(summaryScope)"
                        : "Apple accessibility audit reported issues for \(summaryScope)",
                    detail: completed.issues.isEmpty
                        ? "The Apple XCTest accessibility audit completed on \(summaryScope) without reporting issues."
                        : "The Apple XCTest accessibility audit completed on \(summaryScope) and reported issues that should be fixed before relying on accessibility automation alone.",
                    fix: completed.issues.isEmpty
                        ? "Continue with broader workflow coverage for onboarding, empty, detail, and settings screens."
                        : "Resolve the reported accessibility audit issues, then rerun preflight and manual VoiceOver or Voice Control checks on the same workflow.",
                    evidence: [
                        "issue_count=\(completed.issues.count)",
                        "report_path=\(completed.reportPath)"
                    ],
                    file: nil,
                    line: nil,
                    verifiedBy: "apple_accessibility_audit"
                )
            ]

            findings.append(contentsOf: completed.issues.map { issue in
                let semanticMatch = resolveSemanticElement(for: issue, in: semanticSnapshot)
                var evidence = [
                    "audit_type=\(issue.auditType)",
                    "report_path=\(completed.reportPath)"
                ]
                if let elementDescription = issue.elementDescription, !elementDescription.isEmpty {
                    evidence.append("element=\(elementDescription)")
                }
                if let elementIdentifier = issue.elementIdentifier, !elementIdentifier.isEmpty {
                    evidence.append("element_identifier=\(elementIdentifier)")
                }
                if let elementLabel = issue.elementLabel, !elementLabel.isEmpty {
                    evidence.append("element_label=\(elementLabel)")
                }
                if let elementType = issue.elementType, !elementType.isEmpty {
                    evidence.append("element_type=\(elementType)")
                }
                if let semanticMatch {
                    evidence.append("semantic_element_id=\(semanticMatch.element.elementID)")
                    evidence.append("semantic_match=\(semanticMatch.matchKind)")
                    if let sourceFile = semanticMatch.element.sourceFile, !sourceFile.isEmpty {
                        evidence.append("semantic_source_file=\(sourceFile)")
                    }
                    if let sourceLine = semanticMatch.element.sourceLine {
                        evidence.append("semantic_source_line=\(sourceLine)")
                    }
                }

                return Finding(
                    platform: "ios",
                    surface: "accessibility_audit",
                    severity: .warn,
                    confidence: .proven,
                    title: "Apple accessibility audit reported a \(prettyAuditType(issue.auditType)) issue",
                    detail: issue.compactDescription,
                    fix: issue.detailedDescription,
                    evidence: evidence,
                    file: semanticMatch?.element.sourceFile,
                    line: semanticMatch?.element.sourceLine,
                    verifiedBy: "apple_accessibility_audit"
                )
            })

            if let metadataGapFinding = makeMissingAuditMetadataFinding(
                from: completed.issues,
                semanticSnapshot: semanticSnapshot,
                reportPath: completed.reportPath
            ) {
                findings.append(metadataGapFinding)
            }

            return findings
        }
    }

    func makeAccessibilityAuditAssistedChecks(from result: IOSAccessibilityAuditExecutionResult) -> [String] {
        switch result {
        case .skipped:
            return [
                "Run the Apple accessibility audit harness after fixing the harness failure so the current screen gets a first-party XCTest audit."
            ]
        case .completed(let completed) where completed.issues.isEmpty:
            return [
                "Repeat the Apple accessibility audit across onboarding, authentication, empty, detail, and settings screens because XCTest audits only the current screen state."
            ]
        case .completed:
            return [
                "Re-run VoiceOver and Voice Control on the audited screen after fixing the Apple accessibility audit issues.",
                "Repeat the Apple accessibility audit across onboarding, authentication, empty, detail, and settings screens because XCTest audits only the current screen state."
            ]
        }
    }

    func runDeclaredScenarioAudits(
        declaredScenarios: [AppSemanticAuditScenario],
        defaultScreenID: String,
        target: ResolvedBuildTarget,
        build: BuildResult,
        bundleIdentifier: String,
        device: SimulatorDevice,
        baseLaunchEnvironment: [String: String],
        snapshotPath: String,
        snapshotCopySourcePaths: [String]
    ) -> RuntimeVerificationResult {
        let uniqueScenarios = declaredScenarios
            .filter { $0.screenID != defaultScreenID }
            .removingDuplicates(by: \.scenarioID)

        guard !uniqueScenarios.isEmpty else {
            return RuntimeVerificationResult(findings: [], assistedChecks: [], artifacts: [])
        }

        var findings: [Finding] = []
        var assistedChecks: [String] = []
        var artifacts: [String] = []
        var totalCoveredScreens = 1
        var totalIssueCount = 0
        var executedScenarioLabels: [String] = []
        var skippedScenarioLabels: [String] = []

        for scenario in uniqueScenarios {
            let launchEnvironment = scenarioLaunchEnvironment(
                base: baseLaunchEnvironment,
                scenarioID: scenario.scenarioID
            )
            let scenarioResult = accessibilityAuditRunner.run(
                bundleIdentifier: bundleIdentifier,
                appPath: build.buildPath,
                launchEnvironment: launchEnvironment,
                containerKind: target.containerKind,
                containerName: target.containerName,
                containerPath: target.containerPath,
                projectPath: target.projectPath,
                targetName: target.buildableName.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? build.scheme,
                on: device
            )

            artifacts.append(contentsOf: makeAccessibilityAuditArtifacts(from: scenarioResult))

            let scenarioSnapshot = readScenarioSemanticSnapshot(
                at: snapshotPath,
                snapshotCopySourcePaths: snapshotCopySourcePaths
            )
            findings.append(contentsOf: scenarioSnapshot.warnings)

            switch scenarioResult {
            case .completed(let completed):
                findings.append(
                    contentsOf: makeAccessibilityAuditFindings(
                        from: scenarioResult,
                        semanticSnapshot: scenarioSnapshot.snapshot,
                        summaryScope: "scenario \(scenario.label)"
                    )
                )
                totalCoveredScreens += 1
                totalIssueCount += completed.issues.count
                executedScenarioLabels.append(scenario.label)
                if let scenarioSnapshot = scenarioSnapshot.snapshot,
                   scenarioSnapshot.screenID != scenario.screenID {
                    findings.append(
                        Finding(
                            platform: "ios",
                            surface: "runtime",
                            severity: .warn,
                            confidence: .assisted,
                            title: "Audit scenario launched a different screen than declared",
                            detail: "The app declared one audit screen but exported a different semantic screen during the scenario run.",
                            fix: "Align the app's accessibility preflight scenario mapping so the declared screen and exported semantic screen stay in sync.",
                            evidence: [
                                "scenario_id=\(scenario.scenarioID)",
                                "declared_screen_id=\(scenario.screenID)",
                                "exported_screen_id=\(scenarioSnapshot.screenID)"
                            ],
                            file: nil,
                            line: nil,
                            verifiedBy: "app_semantic"
                        )
                    )
                }
            case .skipped(let reason):
                skippedScenarioLabels.append(scenario.label)
                findings.append(
                    Finding(
                        platform: "ios",
                        surface: "accessibility_audit",
                        severity: .warn,
                        confidence: .assisted,
                        title: "Apple accessibility audit could not run automatically",
                        detail: "The runtime verifier could not complete the Apple XCTest accessibility audit for declared scenario \(scenario.label).",
                        fix: "Review the scenario launch wiring, then rerun preflight so the declared screen participates in the automated audit matrix.",
                        evidence: [
                            "scenario_id=\(scenario.scenarioID)",
                            "screen_id=\(scenario.screenID)",
                            "reason=\(reason)"
                        ],
                        file: nil,
                        line: nil,
                        verifiedBy: "apple_accessibility_audit"
                    )
                )
            }
        }

        findings.append(
            Finding(
                platform: "ios",
                surface: "accessibility_audit",
                severity: totalIssueCount == 0 && skippedScenarioLabels.isEmpty ? .info : .warn,
                confidence: skippedScenarioLabels.isEmpty ? .proven : .assisted,
                title: totalIssueCount == 0 && skippedScenarioLabels.isEmpty
                    ? "Apple accessibility audit matrix passed for \(totalCoveredScreens) declared iOS screens"
                    : "Apple accessibility audit matrix reported follow-up across \(totalCoveredScreens) declared iOS screens",
                detail: totalIssueCount == 0 && skippedScenarioLabels.isEmpty
                    ? "The verifier exercised the declared iOS audit matrix without reporting Apple audit issues on the covered screens."
                    : "The verifier exercised the declared iOS audit matrix, but some covered screens reported issues or could not be exercised automatically.",
                fix: totalIssueCount == 0 && skippedScenarioLabels.isEmpty
                    ? "Keep extending declared scenarios as additional app flows become important release blockers."
                    : "Fix the reported issues or scenario launch gaps, then rerun preflight until the declared audit matrix clears cleanly.",
                evidence: [
                    "covered_screens=\(totalCoveredScreens)",
                    "covered_labels=\((executedScenarioLabels + ["Default launch"]).sorted().joined(separator: ", "))",
                    "matrix_issue_count=\(totalIssueCount)"
                ] + (skippedScenarioLabels.isEmpty ? [] : ["skipped_labels=\(skippedScenarioLabels.sorted().joined(separator: ", "))"]),
                file: nil,
                line: nil,
                verifiedBy: "apple_accessibility_audit_matrix"
            )
        )

        assistedChecks.append(
            "Declared Apple audit matrix covered: \((executedScenarioLabels + ["Default launch"]).sorted().joined(separator: ", "))."
        )
        if !skippedScenarioLabels.isEmpty {
            assistedChecks.append(
                "Repair declared audit scenarios that did not run automatically: \(skippedScenarioLabels.sorted().joined(separator: ", "))."
            )
        }

        return RuntimeVerificationResult(
            findings: findings,
            assistedChecks: assistedChecks,
            artifacts: artifacts.removingDuplicates()
        )
    }

    func makeAccessibilityAuditArtifacts(from result: IOSAccessibilityAuditExecutionResult) -> [String] {
        switch result {
        case .completed(let completed):
            return [completed.reportPath]
        case .skipped:
            return []
        }
    }

    func prettyAuditType(_ rawValue: String) -> String {
        switch rawValue {
        case "contrast":
            return "contrast"
        case "elementDetection":
            return "element detection"
        case "hitRegion":
            return "hit region"
        case "sufficientElementDescription":
            return "element description"
        case "dynamicType":
            return "Dynamic Type"
        case "textClipped":
            return "text clipping"
        case "trait":
            return "trait"
        case "action":
            return "action"
        case "parentChild":
            return "parent-child"
        default:
            return rawValue
        }
    }

    func hasUsefulReadingOrder(_ readingOrder: [String]) -> Bool {
        readingOrder.count >= 2
    }

    func makeMissingAuditMetadataFinding(
        from issues: [IOSAccessibilityAuditIssue],
        semanticSnapshot: AppSemanticSnapshot?,
        reportPath: String
    ) -> Finding? {
        guard let semanticSnapshot else {
            return nil
        }

        let unlabeledIssues = issues.filter(isMissingElementMetadata(_:))
        guard !unlabeledIssues.isEmpty else {
            return nil
        }

        let candidateSources = semanticSnapshot.elements
            .filter(hasUsableSourceLocation(for:))
            .compactMap { element -> String? in
                guard let sourceFile = element.sourceFile,
                      let sourceLine = element.sourceLine else {
                    return nil
                }
                return "\(sourceFile):\(sourceLine)"
            }
            .removingDuplicates()
            .sorted()
        let unmappedAuditTypes = unlabeledIssues
            .map(\.auditType)
            .removingDuplicates()
            .sorted()
            .joined(separator: ", ")

        var evidence = [
            "report_path=\(reportPath)",
            "screen_id=\(semanticSnapshot.screenID)",
            "unmapped_issue_count=\(unlabeledIssues.count)",
            "unmapped_audit_types=\(unmappedAuditTypes)"
        ]
        evidence.append(contentsOf: candidateSources.prefix(8).map { "candidate_source=\($0)" })

        return Finding(
            platform: "ios",
            surface: "accessibility_audit",
            severity: .warn,
            confidence: .assisted,
            title: "Apple accessibility audit omitted element metadata for some issues",
            detail: "Apple reported accessibility issues on this screen without label, identifier, or element type metadata, so exact source mapping is not available for those entries.",
            fix: "Review the candidate source locations on the current semantic screen, fix likely accessibility text or layout issues, then rerun preflight to confirm the unlabeled issues clear.",
            evidence: evidence,
            file: nil,
            line: nil,
            verifiedBy: "apple_accessibility_audit"
        )
    }

    func semanticEvidence(from snapshot: AppSemanticSnapshot, snapshotPath: String) -> [String] {
        var evidence = [
            "app_id=\(snapshot.appID)",
            "screen_id=\(snapshot.screenID)",
            "build_scheme=\(snapshot.buildScheme)",
            "captured_at=\(ISO8601DateFormatter().string(from: snapshot.capturedAt))",
            "snapshot_path=\(snapshotPath)"
        ]
        if let selectedSection = snapshot.selectedSection, !selectedSection.isEmpty {
            evidence.append("selected_section=\(selectedSection)")
        }
        if !snapshot.primaryActions.isEmpty {
            evidence.append("primary_actions=\(snapshot.primaryActions.joined(separator: ", "))")
        }
        if !snapshot.statusSummaries.isEmpty {
            evidence.append("status_summaries=\(snapshot.statusSummaries.joined(separator: " | "))")
        }
        if !snapshot.visibleLabels.isEmpty {
            evidence.append("visible_labels=\(snapshot.visibleLabels.joined(separator: " | "))")
        }
        if !snapshot.elements.isEmpty {
            evidence.append("semantic_elements=\(snapshot.elements.count)")
        }
        if !snapshot.auditScenarios.isEmpty {
            evidence.append("audit_scenarios=\(snapshot.auditScenarios.map(\.screenID).joined(separator: ", "))")
        }
        if let interruptionState = snapshot.interruptionState, !interruptionState.isEmpty {
            evidence.append("interruption_state=\(interruptionState)")
        }
        return evidence
    }

    func semanticAssistedChecks(from snapshot: AppSemanticSnapshot) -> [String] {
        var checks: [String] = []
        if !snapshot.primaryActions.isEmpty {
            checks.append(
                "Review app-declared primary actions during VoiceOver and Voice Control checks: \(snapshot.primaryActions.joined(separator: ", "))"
            )
        }
        if !snapshot.statusSummaries.isEmpty {
            checks.append(
                "Confirm the announced status matches the app semantic summaries: \(snapshot.statusSummaries.joined(separator: " | "))"
            )
        }
        if !snapshot.elements.isEmpty {
            let sourceTaggedElements = snapshot.elements.compactMap { element -> String? in
                guard let sourceFile = element.sourceFile, !sourceFile.isEmpty else {
                    return nil
                }
                if let label = element.label, !label.isEmpty {
                    return "\(label) -> \(sourceFile)"
                }
                return "\(element.elementID) -> \(sourceFile)"
            }
            if !sourceTaggedElements.isEmpty {
                checks.append(
                    "Use the semantic element breadcrumbs to verify source-backed accessibility issues: \(sourceTaggedElements.joined(separator: " | "))"
                )
            }
        }
        if !snapshot.auditScenarios.isEmpty {
            checks.append(
                "Declared audit scenarios available for deeper iOS coverage: \(snapshot.auditScenarios.map(\.label).joined(separator: ", "))"
            )
        }
        return checks
    }

    func scenarioLaunchEnvironment(base: [String: String], scenarioID: String) -> [String: String] {
        var environment = base
        environment["ACCESSIBILITY_PREFLIGHT_AUDIT_SCENARIO"] = scenarioID
        return environment
    }

    func readScenarioSemanticSnapshot(
        at snapshotPath: String,
        snapshotCopySourcePaths: [String]
    ) -> (snapshot: AppSemanticSnapshot?, warnings: [Finding]) {
        do {
            try materializeSemanticSnapshotIfNeeded(
                from: snapshotCopySourcePaths,
                to: snapshotPath,
                refreshExisting: true
            )
            let snapshot = try semanticSnapshotReader.read(from: snapshotPath)
            return (snapshot, [])
        } catch {
            return (
                nil,
                [
                    Finding(
                        platform: "ios",
                        surface: "runtime",
                        severity: .warn,
                        confidence: .assisted,
                        title: "Scenario semantic snapshot could not be read",
                        detail: "A declared audit scenario ran, but the verifier could not read a semantic snapshot for that scenario.",
                        fix: "Confirm the scenario writes a valid semantic snapshot when launched with ACCESSIBILITY_PREFLIGHT_AUDIT_SCENARIO, then rerun preflight.",
                        evidence: [
                            "snapshot_path=\(snapshotPath)",
                            "reason=\(Self.semanticErrorDescription(error))"
                        ],
                        file: nil,
                        line: nil,
                        verifiedBy: "app_semantic"
                    )
                ]
            )
        }
    }

    func resolveSemanticElement(
        for issue: IOSAccessibilityAuditIssue,
        in snapshot: AppSemanticSnapshot?
    ) -> SemanticElementMatch? {
        guard let snapshot else {
            return nil
        }

        if let identifier = normalizedSemanticValue(issue.elementIdentifier),
           let element = snapshot.elements.first(where: {
               normalizedSemanticValue($0.accessibilityIdentifier) == identifier && hasUsableSourceLocation(for: $0)
           }) {
            return SemanticElementMatch(element: element, matchKind: "identifier")
        }

        guard let label = normalizedSemanticValue(issue.elementLabel ?? issue.elementDescription) else {
            return nil
        }

        let matchingElements = snapshot.elements.filter { element in
            guard hasUsableSourceLocation(for: element) else {
                return false
            }
            guard normalizedSemanticValue(element.label) == label else {
                return false
            }
            return semanticRole(element.role, matches: issue)
        }

        guard matchingElements.count == 1, let element = matchingElements.first else {
            return nil
        }

        return SemanticElementMatch(element: element, matchKind: "label")
    }

    func hasUsableSourceLocation(for element: AppSemanticElement) -> Bool {
        guard let sourceFile = element.sourceFile, !sourceFile.isEmpty else {
            return false
        }
        return element.sourceLine != nil
    }

    func semanticRole(_ role: String, matches issue: IOSAccessibilityAuditIssue) -> Bool {
        guard let auditRole = normalizedAuditElementRole(for: issue) else {
            return true
        }
        return normalizedSemanticValue(role) == auditRole
    }

    func normalizedAuditElementRole(for issue: IOSAccessibilityAuditIssue) -> String? {
        if let elementType = normalizedSemanticValue(issue.elementType),
           elementType.hasPrefix("xcuielementtype(rawvalue:") == false {
            return elementType
        }

        guard let elementDescription = issue.elementDescription else {
            return normalizedSemanticValue(issue.elementType)
        }

        let trailingToken = elementDescription
            .split(whereSeparator: \.isWhitespace)
            .last
            .map(String.init)
        return normalizedSemanticValue(trailingToken)
    }

    func normalizedSemanticValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    func isMissingElementMetadata(_ issue: IOSAccessibilityAuditIssue) -> Bool {
        normalizedSemanticValue(issue.elementDescription) == nil &&
            normalizedSemanticValue(issue.elementIdentifier) == nil &&
            normalizedSemanticValue(issue.elementLabel) == nil &&
            normalizedSemanticValue(issue.elementType) == nil
    }

    func materializeSemanticSnapshotIfNeeded(
        from sourcePaths: [String],
        to destinationPath: String,
        refreshExisting: Bool = false
    ) throws {
        if refreshExisting == false, FileManager.default.fileExists(atPath: destinationPath) {
            return
        }

        let fileManager = FileManager.default
        let destinationURL = URL(fileURLWithPath: destinationPath)
        if refreshExisting, fileManager.fileExists(atPath: destinationPath) {
            try fileManager.removeItem(at: destinationURL)
        }
        for sourcePath in sourcePaths where sourcePath != destinationPath {
            guard waitForFile(atPath: sourcePath, using: fileManager) else {
                continue
            }

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            if fileManager.fileExists(atPath: destinationPath) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: URL(fileURLWithPath: sourcePath), to: destinationURL)
            return
        }
    }

    func waitForFile(atPath path: String, using fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: path) {
            return true
        }

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            if fileManager.fileExists(atPath: path) {
                return true
            }
        }

        return false
    }

    static func semanticLaunchRequest(bundleIdentifier: String, outputPath: String? = nil) -> SimulatorLaunchRequest {
        SimulatorLaunchRequest(
            bundleIdentifier: bundleIdentifier,
            environment: semanticLaunchEnvironment(outputPath: outputPath)
        )
    }

    static func semanticLaunchEnvironment(outputPath: String? = nil) -> [String: String] {
        [
            "ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH": outputPath ?? semanticSnapshotPath(),
            "ACCESSIBILITY_PREFLIGHT_SEMANTICS": "1"
        ]
    }

    static func semanticSnapshotPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("accessibility-preflight-\(UUID().uuidString)")
            .appendingPathExtension("json")
            .path
    }

    static func semanticSnapshotDestination(
        bundleIdentifier: String,
        on device: SimulatorDevice,
        requestedHostPath: String,
        using simulatorBootstrap: SimulatorBootstrap
    ) -> SemanticSnapshotDestination {
        guard let containerPath = try? simulatorBootstrap.appDataContainerPath(
            bundleIdentifier: bundleIdentifier,
            on: device
        ) else {
            return SemanticSnapshotDestination(
                appOutputPath: requestedHostPath,
                hostReadPath: requestedHostPath,
                hostContainerPath: nil
            )
        }

        let requestedURL = URL(fileURLWithPath: requestedHostPath)
        let filename = requestedURL.lastPathComponent.isEmpty ? "semantic-snapshot.json" : requestedURL.lastPathComponent
        let appOutputPath = "/tmp/\(filename)"
        let hostContainerPath = URL(fileURLWithPath: containerPath, isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent(filename)
            .path

        return SemanticSnapshotDestination(
            appOutputPath: appOutputPath,
            hostReadPath: requestedHostPath,
            hostContainerPath: hostContainerPath
        )
    }

    static func semanticAppSlug(for target: ResolvedBuildTarget, build: BuildResult) -> String {
        let preferredName = [build.scheme, target.schemeName, XcodeProjectLocator.defaultSchemeName(for: target.projectName)]
            .first(where: { !$0.isEmpty }) ?? "ios-app"
        let lowercase = preferredName.lowercased()
        return lowercase
            .replacingOccurrences(of: ".xcodeproj", with: "")
            .replacingOccurrences(of: " ", with: "-")
    }

    static func semanticErrorDescription(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription, !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }
}

private struct SemanticSnapshotDestination {
    let appOutputPath: String
    let hostReadPath: String
    let hostContainerPath: String?
}

private struct SemanticElementMatch {
    let element: AppSemanticElement
    let matchKind: String
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Array {
    func removingDuplicates<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
