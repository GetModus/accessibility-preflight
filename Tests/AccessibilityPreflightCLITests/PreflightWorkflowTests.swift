import XCTest
@testable import AccessibilityPreflightCLI
import AccessibilityPreflightCore
import AccessibilityPreflightReport

final class PreflightWorkflowTests: XCTestCase {
    func testParseArgumentsCapturesReportInput() throws {
        let options = try parseArguments(["report", "--input", "/tmp/report.json"])

        XCTAssertEqual(options.command, .report)
        XCTAssertEqual(options.reportInput, "/tmp/report.json")
    }

    func testParseArgumentsCapturesChecklistPlatform() throws {
        let options = try parseArguments(["checklists", "--platform", "ios"])

        XCTAssertEqual(options.command, .checklists)
        XCTAssertEqual(options.checklistPlatform, "ios")
    }

    func testParseArgumentsCapturesManualWorkflowPlatform() throws {
        let options = try parseArguments(["manual-workflows", "--platform", "macos"])

        XCTAssertEqual(options.command, .manualWorkflows)
        XCTAssertEqual(options.checklistPlatform, "macos")
    }

    func testParseArgumentsCapturesArtifactAndBranch() throws {
        let options = try parseArguments(["apply-artifact", "--artifact", "/tmp/artifact", "--branch", "codex/a11y-fix"])

        XCTAssertEqual(options.command, .applyArtifact)
        XCTAssertEqual(options.artifactPath, "/tmp/artifact")
        XCTAssertEqual(options.branchName, "codex/a11y-fix")
    }

    func testParseArgumentsRejectsUnsupportedFlag() {
        XCTAssertThrowsError(try parseArguments(["preflight", "--bogus"])) { error in
            XCTAssertEqual(error.localizedDescription, "Unsupported flag --bogus")
        }
    }

    func testScanStaticSourcesSkipsDirectoriesThatEndInSwift() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Fake.swift", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "import SwiftUI\nText(\"Hello\")\n".write(
            to: root.appendingPathComponent("ContentView.swift"),
            atomically: true,
            encoding: .utf8
        )

        let findings = try scanStaticSources(at: root.path, using: .init())

        XCTAssertEqual(findings.count, 0)
    }

    func testExecuteCLIReportRendersExistingReport() async throws {
        let reportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let report = Report(
            findings: [
                Finding(
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
            ],
            assistedChecks: ["Verify VoiceOver order on onboarding screen"]
        )
        try JSONReportWriter.write(report).write(to: reportURL)

        let result = try await executeCLI(arguments: ["report", "--input", reportURL.path])

        XCTAssertTrue(result.output.contains("Accessibility Preflight Report"))
        XCTAssertEqual(result.exitCode, 1)
    }

    func testExecuteCLIChecklistsRendersPlatformChecklist() async throws {
        let result = try await executeCLI(arguments: ["checklists", "--platform", "macos"])

        XCTAssertTrue(result.output.contains("Accessibility Audit Checklist (macOS)"))
        XCTAssertTrue(result.output.contains("Verify keyboard-only reachability"))
        XCTAssertEqual(result.exitCode, 0)
    }

    func testExecuteCLIManualWorkflowsRendersIosWorkflow() async throws {
        let result = try await executeCLI(arguments: ["manual-workflows", "--platform", "ios"])

        XCTAssertTrue(result.output.contains("Manual Assistive-Tech Workflow (iOS)"))
        XCTAssertTrue(result.output.contains("VoiceOver"))
        XCTAssertTrue(result.output.contains("Voice Control"))
        XCTAssertTrue(result.output.contains("Dynamic Type"))
        XCTAssertEqual(result.exitCode, 0)
    }

    func testExecuteCLIHelpRendersUsage() async throws {
        let result = try await executeCLI(arguments: ["help"])

        XCTAssertTrue(result.output.contains("Accessibility Preflight"))
        XCTAssertTrue(result.output.contains("manual-workflows"))
        XCTAssertTrue(result.output.contains("apply-artifact"))
        XCTAssertEqual(result.exitCode, 0)
    }

    func testExecuteCLIIosRunCarriesSemanticWarningEvidenceIntoJsonReport() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projectName = "SemanticFixture.xcodeproj"
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(projectName, isDirectory: true),
            withIntermediateDirectories: true
        )

        let result = try await executeCLI(
            arguments: ["ios-run", "--path", root.path, "--json"],
            dependencies: PreflightDependencies(
                staticScan: { _ in PreflightSliceResult(findings: [], assistedChecks: []) },
                iosRuntime: { _ in
                    PreflightSliceResult(
                        findings: [
                            Finding(
                                platform: "ios",
                                surface: "runtime",
                                severity: .warn,
                                confidence: .assisted,
                                title: "Optional app semantic integration is not installed",
                                detail: "Richer semantic checks are optional and no app code was changed automatically.",
                                fix: "Review the generated artifact and install it only if desired.",
                                evidence: [
                                    "artifact_path=/tmp/.accessibility-preflight/semantic-integration/semanticfixture"
                                ],
                                file: nil,
                                line: nil,
                                verifiedBy: "runtime"
                            )
                        ],
                        assistedChecks: [
                            "Review the generated semantic integration artifact at /tmp/.accessibility-preflight/semantic-integration/semanticfixture"
                        ]
                    )
                },
                macRuntime: { _ in PreflightSliceResult(findings: [], assistedChecks: []) }
            )
        )

        let report = try JSONDecoder().decode(Report.self, from: Data(result.output.utf8))

        XCTAssertEqual(report.findings.first?.title, "Optional app semantic integration is not installed")
        XCTAssertTrue(report.findings.first?.evidence.contains("artifact_path=/tmp/.accessibility-preflight/semantic-integration/semanticfixture") ?? false)
        XCTAssertTrue(
            report.assistedChecks.contains("Review the generated semantic integration artifact at /tmp/.accessibility-preflight/semantic-integration/semanticfixture")
        )
        XCTAssertTrue(
            report.assistedChecks.contains(where: { $0.contains(".accessibility-preflight/remediation/semanticfixture") })
        )
        XCTAssertEqual(result.exitCode, 0)
    }

    func testRuntimeSliceResultCarriesArtifactsIntoAssistedChecks() {
        let slice = runtimeSliceResult(
            from: RuntimeVerificationResult(
                findings: [],
                assistedChecks: ["Review VoiceOver order"],
                artifacts: ["/tmp/snapshot.json", "/tmp/integration-artifact"]
            )
        )

        XCTAssertEqual(
            slice.assistedChecks,
            [
                "Review VoiceOver order",
                "Runtime artifact: /tmp/snapshot.json",
                "Runtime artifact: /tmp/integration-artifact"
            ]
        )
    }

    func testExecuteCLIGeneratesProposalOnlyRemediationArtifactForActionableFindings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("SemanticFixture", isDirectory: true)
        let projectName = "SemanticFixture.xcodeproj"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(projectName, isDirectory: true),
            withIntermediateDirectories: true
        )

        let result = try await executeCLI(
            arguments: ["ios-run", "--path", root.path, "--json"],
            dependencies: PreflightDependencies(
                staticScan: { _ in PreflightSliceResult(findings: [], assistedChecks: []) },
                iosRuntime: { _ in
                    PreflightSliceResult(
                        findings: [
                            Finding(
                                platform: "ios",
                                surface: "accessibility_audit",
                                severity: .warn,
                                confidence: .proven,
                                title: "Apple accessibility audit reported issues for the current iOS screen",
                                detail: "The Apple XCTest accessibility audit found actionable issues.",
                                fix: "Review the issues and apply fixes on a dedicated branch after approval.",
                                evidence: ["issue_count=2"],
                                file: "/tmp/Project/DashboardView.swift",
                                line: 12,
                                verifiedBy: "apple_accessibility_audit"
                            )
                        ],
                        assistedChecks: []
                    )
                },
                macRuntime: { _ in PreflightSliceResult(findings: [], assistedChecks: []) }
            )
        )

        let report = try JSONDecoder().decode(Report.self, from: Data(result.output.utf8))
        let artifactPath = try XCTUnwrap(
            report.assistedChecks.first(where: { $0.contains(".accessibility-preflight/remediation/semanticfixture") })
        )
        XCTAssertTrue(artifactPath.contains("Review the generated remediation artifact at "))

        let artifactDirectory = root
            .appendingPathComponent(".accessibility-preflight", isDirectory: true)
            .appendingPathComponent("remediation", isDirectory: true)
            .appendingPathComponent("semanticfixture", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDirectory.appendingPathComponent("README.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDirectory.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactDirectory.appendingPathComponent("changes.patch").path))
        XCTAssertEqual(result.exitCode, 0)
    }

    func testExecuteCLIApplyArtifactCreatesBranchAndAppliesSynthesizedPatch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("PatchFixture", isDirectory: true)
        let projectName = "PatchFixture.xcodeproj"
        let sourceFile = root.appendingPathComponent("ContentView.swift")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(projectName, isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Text("Hello")
                    .font(.system(size: 16))
            }
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        _ = try runGit(["init", "-b", "main"], in: root.path)
        _ = try runGit(["add", "."], in: root.path)
        _ = try runGit(["commit", "-m", "Initial"], in: root.path)

        let runtimeResult = try await executeCLI(
            arguments: ["ios-run", "--path", root.path, "--json"],
            dependencies: PreflightDependencies(
                staticScan: { _ in PreflightSliceResult(findings: [], assistedChecks: []) },
                iosRuntime: { _ in
                    PreflightSliceResult(
                        findings: [
                            Finding(
                                platform: "shared",
                                surface: "dynamic-type",
                                severity: .warn,
                                confidence: .heuristic,
                                title: "Fixed font point size",
                                detail: "Detected text styled with a fixed system font size instead of dynamic type-aware styles.",
                                fix: "Use a text style such as .body or .headline and let Dynamic Type scale it.",
                                evidence: ["static rule: fixed point font size"],
                                file: sourceFile.path,
                                line: nil,
                                verifiedBy: "static"
                            )
                        ],
                        assistedChecks: []
                    )
                },
                macRuntime: { _ in PreflightSliceResult(findings: [], assistedChecks: []) }
            )
        )

        let report = try JSONDecoder().decode(Report.self, from: Data(runtimeResult.output.utf8))
        let artifactCheck = try XCTUnwrap(report.assistedChecks.first(where: { $0.contains(".accessibility-preflight/remediation/patchfixture") }))
        let artifactPath = artifactCheck.replacingOccurrences(of: "Review the generated remediation artifact at ", with: "")

        let applyResult = try await executeCLI(
            arguments: ["apply-artifact", "--artifact", artifactPath, "--branch", "codex/a11y-fixed-font"],
            dependencies: makeLiveDependencies()
        )

        XCTAssertTrue(applyResult.output.contains("Applied remediation artifact"))
        XCTAssertTrue(applyResult.output.contains("codex/a11y-fixed-font"))

        let branch = try runGit(["branch", "--show-current"], in: root.path).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(branch, "codex/a11y-fixed-font")

        let updatedSource = try String(contentsOf: sourceFile, encoding: .utf8)
        XCTAssertTrue(updatedSource.contains(".font(.body)"))
        XCTAssertFalse(updatedSource.contains(".font(.system(size: 16))"))
    }

    func testExecuteCLIApplyArtifactPreservesSystemFontWeightAndDesign() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("WeightedPatchFixture", isDirectory: true)
        let projectName = "WeightedPatchFixture.xcodeproj"
        let sourceFile = root.appendingPathComponent("ContentView.swift")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(projectName, isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Text("Hello")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        _ = try runGit(["init", "-b", "main"], in: root.path)
        _ = try runGit(["add", "."], in: root.path)
        _ = try runGit(["commit", "-m", "Initial"], in: root.path)

        let runtimeResult = try await executeCLI(
            arguments: ["ios-run", "--path", root.path, "--json"],
            dependencies: PreflightDependencies(
                staticScan: { _ in PreflightSliceResult(findings: [], assistedChecks: []) },
                iosRuntime: { _ in
                    PreflightSliceResult(
                        findings: [
                            Finding(
                                platform: "shared",
                                surface: "dynamic-type",
                                severity: .warn,
                                confidence: .heuristic,
                                title: "Fixed font point size",
                                detail: "Detected text styled with a fixed system font size instead of dynamic type-aware styles.",
                                fix: "Use a text style such as .body or .headline and let Dynamic Type scale it.",
                                evidence: ["static rule: fixed point font size"],
                                file: sourceFile.path,
                                line: nil,
                                verifiedBy: "static"
                            )
                        ],
                        assistedChecks: []
                    )
                },
                macRuntime: { _ in PreflightSliceResult(findings: [], assistedChecks: []) }
            )
        )

        let report = try JSONDecoder().decode(Report.self, from: Data(runtimeResult.output.utf8))
        let artifactCheck = try XCTUnwrap(report.assistedChecks.first(where: { $0.contains(".accessibility-preflight/remediation/weightedpatchfixture") }))
        let artifactPath = artifactCheck.replacingOccurrences(of: "Review the generated remediation artifact at ", with: "")

        _ = try await executeCLI(
            arguments: ["apply-artifact", "--artifact", artifactPath, "--branch", "codex/a11y-weighted-font"],
            dependencies: makeLiveDependencies()
        )

        let updatedSource = try String(contentsOf: sourceFile, encoding: .utf8)
        XCTAssertTrue(updatedSource.contains(".font(.system(.body, design: .rounded, weight: .semibold))"))
        XCTAssertFalse(updatedSource.contains(".font(.system(size: 16, weight: .semibold, design: .rounded))"))
    }

    func testExecuteCLIApplyArtifactAddsRelativeTextStyleForCustomFonts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("CustomFontFixture", isDirectory: true)
        let projectName = "CustomFontFixture.xcodeproj"
        let sourceFile = root.appendingPathComponent("ContentView.swift")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(projectName, isDirectory: true),
            withIntermediateDirectories: true
        )
        try #"""
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Text("Hello")
                    .font(.custom("Inter", size: 16))
            }
        }
        """#.write(to: sourceFile, atomically: true, encoding: .utf8)

        _ = try runGit(["init", "-b", "main"], in: root.path)
        _ = try runGit(["add", "."], in: root.path)
        _ = try runGit(["commit", "-m", "Initial"], in: root.path)

        let runtimeResult = try await executeCLI(
            arguments: ["ios-run", "--path", root.path, "--json"],
            dependencies: PreflightDependencies(
                staticScan: { _ in PreflightSliceResult(findings: [], assistedChecks: []) },
                iosRuntime: { _ in
                    PreflightSliceResult(
                        findings: [
                            Finding(
                                platform: "shared",
                                surface: "dynamic-type",
                                severity: .warn,
                                confidence: .heuristic,
                                title: "Fixed custom font point size",
                                detail: "Detected a custom font using a fixed point size without a relative text style.",
                                fix: "Add a relative text style so the custom font scales with Dynamic Type.",
                                evidence: ["static rule: fixed custom font size without relative text style"],
                                file: sourceFile.path,
                                line: nil,
                                verifiedBy: "static"
                            )
                        ],
                        assistedChecks: []
                    )
                },
                macRuntime: { _ in PreflightSliceResult(findings: [], assistedChecks: []) }
            )
        )

        let report = try JSONDecoder().decode(Report.self, from: Data(runtimeResult.output.utf8))
        let artifactCheck = try XCTUnwrap(report.assistedChecks.first(where: { $0.contains(".accessibility-preflight/remediation/customfontfixture") }))
        let artifactPath = artifactCheck.replacingOccurrences(of: "Review the generated remediation artifact at ", with: "")

        _ = try await executeCLI(
            arguments: ["apply-artifact", "--artifact", artifactPath, "--branch", "codex/a11y-custom-font"],
            dependencies: makeLiveDependencies()
        )

        let updatedSource = try String(contentsOf: sourceFile, encoding: .utf8)
        XCTAssertTrue(updatedSource.contains(#".font(.custom("Inter", size: 16, relativeTo: .body))"#))
        XCTAssertFalse(updatedSource.contains(#".font(.custom("Inter", size: 16))"#))
    }

    func testExecuteCLIApplyArtifactReplacesGenericLabelWithLiteralButtonTitle() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("GenericLabelFixture", isDirectory: true)
        let projectName = "GenericLabelFixture.xcodeproj"
        let sourceFile = root.appendingPathComponent("ContentView.swift")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(projectName, isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Button("Done") {}
                    .accessibilityLabel("Button")
            }
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        _ = try runGit(["init", "-b", "main"], in: root.path)
        _ = try runGit(["add", "."], in: root.path)
        _ = try runGit(["commit", "-m", "Initial"], in: root.path)

        let runtimeResult = try await executeCLI(
            arguments: ["ios-run", "--path", root.path, "--json"],
            dependencies: PreflightDependencies(
                staticScan: { _ in PreflightSliceResult(findings: [], assistedChecks: []) },
                iosRuntime: { _ in
                    PreflightSliceResult(
                        findings: [
                            Finding(
                                platform: "shared",
                                surface: "voiceover",
                                severity: .warn,
                                confidence: .heuristic,
                                title: "Generic accessibility label",
                                detail: "Detected an accessibility label that does not describe the control to a user.",
                                fix: "Replace the generic label with a label that reflects the control's purpose.",
                                evidence: ["static rule: generic label"],
                                file: sourceFile.path,
                                line: nil,
                                verifiedBy: "static"
                            )
                        ],
                        assistedChecks: []
                    )
                },
                macRuntime: { _ in PreflightSliceResult(findings: [], assistedChecks: []) }
            )
        )

        let report = try JSONDecoder().decode(Report.self, from: Data(runtimeResult.output.utf8))
        let artifactCheck = try XCTUnwrap(report.assistedChecks.first(where: { $0.contains(".accessibility-preflight/remediation/genericlabelfixture") }))
        let artifactPath = artifactCheck.replacingOccurrences(of: "Review the generated remediation artifact at ", with: "")

        _ = try await executeCLI(
            arguments: ["apply-artifact", "--artifact", artifactPath, "--branch", "codex/a11y-generic-label"],
            dependencies: makeLiveDependencies()
        )

        let updatedSource = try String(contentsOf: sourceFile, encoding: .utf8)
        XCTAssertTrue(updatedSource.contains(#".accessibilityLabel("Done")"#))
        XCTAssertFalse(updatedSource.contains(#".accessibilityLabel("Button")"#))
    }

    func testExecuteCLIApplyArtifactReplacesGenericLabelFromTextButtonLabelClosure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("GenericClosureLabelFixture", isDirectory: true)
        let projectName = "GenericClosureLabelFixture.xcodeproj"
        let sourceFile = root.appendingPathComponent("ContentView.swift")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(projectName, isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                }
                .accessibilityLabel("Button")
            }

            private func dismiss() {}
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        _ = try runGit(["init", "-b", "main"], in: root.path)
        _ = try runGit(["add", "."], in: root.path)
        _ = try runGit(["commit", "-m", "Initial"], in: root.path)

        let runtimeResult = try await executeCLI(
            arguments: ["ios-run", "--path", root.path, "--json"],
            dependencies: PreflightDependencies(
                staticScan: { _ in PreflightSliceResult(findings: [], assistedChecks: []) },
                iosRuntime: { _ in
                    PreflightSliceResult(
                        findings: [
                            Finding(
                                platform: "shared",
                                surface: "voiceover",
                                severity: .warn,
                                confidence: .heuristic,
                                title: "Generic accessibility label",
                                detail: "Detected an accessibility label that does not describe the control to a user.",
                                fix: "Replace the generic label with a label that reflects the control's purpose.",
                                evidence: ["static rule: generic label"],
                                file: sourceFile.path,
                                line: nil,
                                verifiedBy: "static"
                            )
                        ],
                        assistedChecks: []
                    )
                },
                macRuntime: { _ in PreflightSliceResult(findings: [], assistedChecks: []) }
            )
        )

        let report = try JSONDecoder().decode(Report.self, from: Data(runtimeResult.output.utf8))
        let artifactCheck = try XCTUnwrap(report.assistedChecks.first(where: { $0.contains(".accessibility-preflight/remediation/genericclosurelabelfixture") }))
        let artifactPath = artifactCheck.replacingOccurrences(of: "Review the generated remediation artifact at ", with: "")

        _ = try await executeCLI(
            arguments: ["apply-artifact", "--artifact", artifactPath, "--branch", "codex/a11y-generic-closure-label"],
            dependencies: makeLiveDependencies()
        )

        let updatedSource = try String(contentsOf: sourceFile, encoding: .utf8)
        XCTAssertTrue(updatedSource.contains(#".accessibilityLabel("Continue")"#))
        XCTAssertFalse(updatedSource.contains(#".accessibilityLabel("Button")"#))
    }
}

private func runGit(_ arguments: [String], in workingDirectory: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
    process.environment = ProcessInfo.processInfo.environment.merging(
        [
            "GIT_AUTHOR_NAME": "Codex",
            "GIT_AUTHOR_EMAIL": "codex@example.com",
            "GIT_COMMITTER_NAME": "Codex",
            "GIT_COMMITTER_EMAIL": "codex@example.com"
        ]
    ) { _, new in new }

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "PreflightWorkflowTests.git",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: String(decoding: stderrData, as: UTF8.self)]
        )
    }

    return String(decoding: stdoutData, as: UTF8.self)
}
