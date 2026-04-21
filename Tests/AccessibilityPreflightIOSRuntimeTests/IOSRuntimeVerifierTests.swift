import XCTest
@testable import AccessibilityPreflightIOSRuntime
import AccessibilityPreflightBuild
import AccessibilityPreflightCore
import AccessibilityPreflightReport

final class IOSRuntimeVerifierTests: XCTestCase {
    func testRuntimeVerificationResultRetainsArtifactsCompatibility() {
        let result = RuntimeVerificationResult(
            findings: [],
            assistedChecks: ["check"],
            artifacts: ["/tmp/artifact.json"]
        )

        XCTAssertEqual(result.assistedChecks, ["check"])
        XCTAssertEqual(result.artifacts, ["/tmp/artifact.json"])
    }

    func testScenarioSemanticSnapshotRefreshesExistingHostCopy() throws {
        let verifier = IOSRuntimeVerifier()
        let fileManager = FileManager.default
        let workspaceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ios-runtime-verifier-tests-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = workspaceRoot.appendingPathComponent("source-snapshot.json")
        let destinationURL = workspaceRoot.appendingPathComponent("host-snapshot.json")

        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        try writeSemanticSnapshot(screenID: "onboarding.identityHook", to: sourceURL)
        try verifier.testingMaterializeSemanticSnapshot(
            from: [sourceURL.path],
            to: destinationURL.path
        )

        try writeSemanticSnapshot(screenID: "settings.preferences", to: sourceURL)
        let refreshedSnapshot = verifier.testingReadScenarioSemanticSnapshot(
            at: destinationURL.path,
            snapshotCopySourcePaths: [sourceURL.path]
        )

        XCTAssertTrue(refreshedSnapshot.warnings.isEmpty)
        XCTAssertEqual(refreshedSnapshot.snapshot?.screenID, "settings.preferences")
    }

    func testIncludesDynamicTypeAssistedCheck() async throws {
        let result = try await IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in
                    SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
                },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, device in
                    SimulatorLaunchResult(
                        device: device,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "123: com.enclave.app"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: makeStubAccessibilityAuditRunner(),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: [],
                    readingOrder: [],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            })
        ).verify(projectRoot: "/tmp/Project", simulatorID: "booted")

        XCTAssertTrue(result.assistedChecks.contains("Review Voice Control targeting for primary actions after the clean-install and relaunch sequence."))
    }

    func testSkipsReadingOrderArtifactWhenOcrIsTooSparse() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let result = try await IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.enclave.app: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: makeStubAccessibilityAuditRunner(),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, label in
                if label == "default" {
                    return SimulatorScreenInspectionResult(
                        screenshotPath: "/tmp/default.png",
                        recognizedTexts: ["MODUS"],
                        readingOrder: ["MODUS"],
                        duplicateCommandNames: [],
                        truncationCandidates: [],
                        crowdedTextPairs: []
                    )
                }

                return SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/dynamic.png",
                    recognizedTexts: [],
                    readingOrder: [],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            })
        ).verify(projectRoot: "/tmp/Project", simulatorID: "booted")

        XCTAssertFalse(result.assistedChecks.contains(where: { $0.contains("Compare VoiceOver focus order against this on-screen reading order") }))
    }

    func testEmitsProvenFindingsForLaunchSequenceAndDynamicTypeSweep() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let callLog = LockedCallLog()
        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { simulatorID in
                    XCTAssertEqual(simulatorID, "booted")
                    callLog.append("resolve:\(simulatorID)")
                    return device
                },
                uninstallApp: { bundleIdentifier, resolvedDevice in
                    XCTAssertEqual(bundleIdentifier, "com.enclave.app")
                    XCTAssertEqual(resolvedDevice, device)
                    callLog.append("uninstall:\(bundleIdentifier)")
                },
                installApp: { appPath, resolvedDevice in
                    XCTAssertEqual(appPath, "/tmp/Derived/Enclave.app")
                    XCTAssertEqual(resolvedDevice, device)
                    callLog.append("install:\(appPath)")
                },
                terminateApp: { bundleIdentifier, resolvedDevice in
                    XCTAssertEqual(bundleIdentifier, "com.enclave.app")
                    XCTAssertEqual(resolvedDevice, device)
                    callLog.append("terminate:\(bundleIdentifier)")
                },
                launchApp: { request, resolvedDevice in
                    XCTAssertEqual(request.bundleIdentifier, "com.enclave.app")
                    XCTAssertEqual(resolvedDevice, device)
                    XCTAssertEqual(request.environment["ACCESSIBILITY_PREFLIGHT_SEMANTICS"], "1")
                    XCTAssertFalse(request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"]?.isEmpty ?? true)
                    let launchNumber = callLog.count(matchingPrefix: "launch:") + 1
                    callLog.append("launch:\(launchNumber)")
                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: String(100 + launchNumber),
                        launchOutput: "com.enclave.app: \(100 + launchNumber)"
                    )
                },
                contentSizeCategory: { resolvedDevice in
                    XCTAssertEqual(resolvedDevice, device)
                    callLog.append("content-size:get")
                    return "large"
                },
                setContentSizeCategory: { category, resolvedDevice in
                    XCTAssertEqual(resolvedDevice, device)
                    callLog.append("content-size:set:\(category)")
                }
            ),
            accessibilityAuditRunner: IOSAccessibilityAuditRunner(run: { bundleIdentifier, resolvedDevice in
                XCTAssertEqual(bundleIdentifier, "com.enclave.app")
                XCTAssertEqual(resolvedDevice, device)
                callLog.append("audit:\(bundleIdentifier)")
                return .completed(IOSAccessibilityAuditCompleted(reportPath: "/tmp/apple-audit.json", issues: []))
            }),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { resolvedDevice, label in
                XCTAssertEqual(resolvedDevice, device)
                callLog.append("inspect:\(label)")
                if label == "default" {
                    return SimulatorScreenInspectionResult(
                        screenshotPath: "/tmp/default.png",
                        recognizedTexts: ["Continue", "Settings", "Continue"],
                        readingOrder: ["Continue", "Settings", "Continue"],
                        duplicateCommandNames: ["Continue"],
                        truncationCandidates: [],
                        crowdedTextPairs: []
                    )
                }

                return SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/dynamic.png",
                    recognizedTexts: ["Very long account settin…", "Permission", "Permission details"],
                    readingOrder: ["Very long account settin…", "Permission", "Permission details"],
                    duplicateCommandNames: [],
                    truncationCandidates: ["Very long account settin…"],
                    crowdedTextPairs: ["Permission <> Permission details"]
                )
            })
        )

        let result = try await verifier.verify(projectRoot: "/tmp/Project", simulatorID: "booted")

        let launchSequenceFinding = try XCTUnwrap(result.findings.first(where: { $0.title == "iOS clean-install launch sequence succeeded" }))
        XCTAssertEqual(launchSequenceFinding.confidence, Confidence.proven)
        XCTAssertTrue(launchSequenceFinding.evidence.contains("device=iPhone 17 (booted-device)"))
        XCTAssertTrue(launchSequenceFinding.evidence.contains("bundle_id=com.enclave.app"))
        XCTAssertTrue(launchSequenceFinding.evidence.contains("first_launch_pid=101"))
        XCTAssertTrue(launchSequenceFinding.evidence.contains("relaunch_pid=102"))

        let dynamicTypeFinding = try XCTUnwrap(result.findings.first(where: { $0.title == "Dynamic Type accessibility launch succeeded" }))
        XCTAssertEqual(dynamicTypeFinding.confidence, Confidence.proven)
        XCTAssertTrue(dynamicTypeFinding.evidence.contains("original_content_size=large"))
        XCTAssertTrue(dynamicTypeFinding.evidence.contains("audited_content_size=accessibility-extra-extra-extra-large"))
        XCTAssertTrue(dynamicTypeFinding.evidence.contains("dynamic_type_launch_pid=103"))
        XCTAssertTrue(dynamicTypeFinding.evidence.contains("screenshot=/tmp/dynamic.png"))

        let voiceControlFinding = try XCTUnwrap(result.findings.first(where: { $0.title == "Visible command names may be ambiguous for Voice Control" }))
        XCTAssertEqual(voiceControlFinding.confidence, Confidence.heuristic)
        XCTAssertTrue(voiceControlFinding.evidence.contains("duplicates=Continue"))
        XCTAssertTrue(voiceControlFinding.evidence.contains("screenshot=/tmp/default.png"))

        let truncationFinding = try XCTUnwrap(result.findings.first(where: { $0.title == "Text may be truncated at accessibility Dynamic Type size" }))
        XCTAssertEqual(truncationFinding.confidence, Confidence.heuristic)
        XCTAssertTrue(truncationFinding.evidence.contains("candidates=Very long account settin…"))

        let crowdedFinding = try XCTUnwrap(result.findings.first(where: { $0.title == "Text regions appear crowded at accessibility Dynamic Type size" }))
        XCTAssertEqual(crowdedFinding.confidence, Confidence.heuristic)
        XCTAssertTrue(crowdedFinding.evidence.contains("pairs=Permission <> Permission details"))

        XCTAssertTrue(result.assistedChecks.contains("Review the screens exercised at accessibility-extra-extra-extra-large for clipping, truncation, and overlap."))
        XCTAssertTrue(result.assistedChecks.contains("Compare VoiceOver focus order against this on-screen reading order: Continue -> Settings -> Continue"))
        XCTAssertEqual(
            callLog.values,
            [
                "resolve:booted",
                "terminate:com.enclave.app",
                "uninstall:com.enclave.app",
                "install:/tmp/Derived/Enclave.app",
                "launch:1",
                "terminate:com.enclave.app",
                "launch:2",
                "inspect:default",
                "audit:com.enclave.app",
                "content-size:get",
                "content-size:set:accessibility-extra-extra-extra-large",
                "terminate:com.enclave.app",
                "launch:3",
                "inspect:dynamic-type",
                "content-size:set:large"
            ]
        )
    }

    func testAddsAssistedFindingWhenDynamicTypeSweepCannotRun() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let result = try await IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.enclave.app: 123"
                    )
                },
                contentSizeCategory: { _ in
                    throw SimulatorBootstrapError.uiConfigurationFailed("unsupported")
                },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: makeStubAccessibilityAuditRunner(),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: [],
                    readingOrder: [],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            })
        ).verify(projectRoot: "/tmp/Project", simulatorID: "booted")

        let finding = try XCTUnwrap(result.findings.first(where: { $0.title == "Dynamic Type sweep requires manual follow-up" }))
        XCTAssertEqual(finding.confidence, Confidence.assisted)
        XCTAssertEqual(finding.severity, Severity.warn)
    }

    func testMergesAppleAccessibilityAuditIssuesIntoRuntimeReport() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let callLog = LockedCallLog()
        let result = try await IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    callLog.append("launch:\(request.bundleIdentifier)")
                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.enclave.app: 123"
                    )
                },
                contentSizeCategory: { _ in
                    callLog.append("content-size:get")
                    return "large"
                },
                setContentSizeCategory: { category, _ in
                    callLog.append("content-size:set:\(category)")
                }
            ),
            accessibilityAuditRunner: IOSAccessibilityAuditRunner(run: { bundleIdentifier, resolvedDevice in
                XCTAssertEqual(bundleIdentifier, "com.enclave.app")
                XCTAssertEqual(resolvedDevice, device)
                callLog.append("audit:\(bundleIdentifier)")
                return .completed(
                    IOSAccessibilityAuditCompleted(
                        reportPath: "/tmp/apple-audit.json",
                        issues: [
                            IOSAccessibilityAuditIssue(
                                auditType: "hitRegion",
                                compactDescription: "Continue button has a small hit target.",
                                detailedDescription: "Increase the tappable region for the Continue button so the control meets the expected hit area.",
                                elementDescription: "Button, Continue",
                                elementIdentifier: "continue-button",
                                elementLabel: "Continue",
                                elementType: "Button"
                            )
                        ]
                    )
                )
            }),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, label in
                callLog.append("inspect:\(label)")
                return SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/\(label).png",
                    recognizedTexts: [],
                    readingOrder: [],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            })
        ).verify(projectRoot: "/tmp/Project", simulatorID: "booted")

        let summaryFinding = try XCTUnwrap(result.findings.first(where: { $0.title == "Apple accessibility audit reported issues for the current iOS screen" }))
        XCTAssertEqual(summaryFinding.confidence, Confidence.proven)
        XCTAssertTrue(summaryFinding.evidence.contains("issue_count=1"))
        XCTAssertTrue(summaryFinding.evidence.contains("report_path=/tmp/apple-audit.json"))

        let issueFinding = try XCTUnwrap(result.findings.first(where: { $0.title == "Apple accessibility audit reported a hit region issue" }))
        XCTAssertEqual(issueFinding.severity, Severity.warn)
        XCTAssertEqual(issueFinding.confidence, Confidence.proven)
        XCTAssertEqual(issueFinding.detail, "Continue button has a small hit target.")
        XCTAssertTrue(issueFinding.evidence.contains("audit_type=hitRegion"))
        XCTAssertTrue(issueFinding.evidence.contains("element_identifier=continue-button"))
        XCTAssertTrue(issueFinding.evidence.contains("element_label=Continue"))

        XCTAssertTrue(result.assistedChecks.contains("Re-run VoiceOver and Voice Control on the audited screen after fixing the Apple accessibility audit issues."))
        XCTAssertTrue(result.artifacts.contains("/tmp/apple-audit.json"))
        XCTAssertEqual(
            callLog.values,
            [
                "launch:com.enclave.app",
                "launch:com.enclave.app",
                "inspect:default",
                "audit:com.enclave.app",
                "content-size:get",
                "content-size:set:accessibility-extra-extra-extra-large",
                "launch:com.enclave.app",
                "inspect:dynamic-type",
                "content-size:set:large"
            ]
        )
    }

    func testDynamicTypePassRestoresOriginalContentSizeAfterLaunchFailure() {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let callLog = LockedCallLog()
        let pass = DynamicTypePass()
        let bootstrap = SimulatorBootstrap(
            resolveDevice: { _ in device },
            uninstallApp: { _, _ in },
            installApp: { _, _ in },
            terminateApp: { _, _ in },
            launchApp: { _, _ in
                callLog.append("launch")
                throw SimulatorBootstrapError.launchFailed("boom")
            },
            contentSizeCategory: { resolvedDevice in
                XCTAssertEqual(resolvedDevice, device)
                callLog.append("content-size:get")
                return "large"
            },
            setContentSizeCategory: { category, resolvedDevice in
                XCTAssertEqual(resolvedDevice, device)
                callLog.append("content-size:set:\(category)")
            }
        )

        let result = pass.run(bundleIdentifier: "com.enclave.app", on: device, using: bootstrap)

        guard case .skipped(let reason) = result else {
            return XCTFail("Expected dynamic type pass to skip after launch failure")
        }

        XCTAssertTrue(reason.contains("boom"))
        XCTAssertEqual(
            callLog.values,
            [
                "content-size:get",
                "content-size:set:accessibility-extra-extra-extra-large",
                "launch",
                "content-size:set:large"
            ]
        )
    }

    func testDynamicTypePassRestoresOriginalContentSizeAfterAuditedWorkFailure() {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let callLog = LockedCallLog()
        let pass = DynamicTypePass()
        let bootstrap = SimulatorBootstrap(
            resolveDevice: { _ in device },
            uninstallApp: { _, _ in },
            installApp: { _, _ in },
            terminateApp: { _, _ in },
            launchApp: { _, _ in
                callLog.append("launch")
                return SimulatorLaunchResult(
                    device: device,
                    bundleIdentifier: "com.enclave.app",
                    processIdentifier: "123",
                    launchOutput: "com.enclave.app: 123"
                )
            },
            contentSizeCategory: { resolvedDevice in
                XCTAssertEqual(resolvedDevice, device)
                callLog.append("content-size:get")
                return "large"
            },
            setContentSizeCategory: { category, resolvedDevice in
                XCTAssertEqual(resolvedDevice, device)
                callLog.append("content-size:set:\(category)")
            }
        )

        let result = pass.run(bundleIdentifier: "com.enclave.app", on: device, using: bootstrap) {
            callLog.append("audited-work")
            throw SimulatorBootstrapError.uiConfigurationFailed("inspection failed")
        }

        guard case .skipped(let reason) = result else {
            return XCTFail("Expected dynamic type pass to skip after audited work failure")
        }

        XCTAssertTrue(reason.contains("inspection failed"))
        XCTAssertEqual(
            callLog.values,
            [
                "content-size:get",
                "content-size:set:accessibility-extra-extra-extra-large",
                "launch",
                "audited-work",
                "content-size:set:large"
            ]
        )
    }

    func testSimulatorBootstrapLaunchIncludesEnvironmentArgumentsAndParsesPid() throws {
        let deviceListJSON = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
              {
                "name": "iPhone 17",
                "udid": "booted-device",
                "state": "Booted",
                "isAvailable": true
              }
            ]
          }
        }
        """
        var launchInvocation: CommandInvocation?
        let bootstrap = SimulatorBootstrap(commandRunner: { invocation in
            launchInvocation = invocation
            switch invocation.arguments.joined(separator: " ") {
            case let arguments where arguments.contains("simctl list devices available -j"):
                return CommandResult(stdout: deviceListJSON, stderr: "", exitCode: 0)
            case "simctl launch booted-device com.enclave.app":
                return CommandResult(stdout: "com.enclave.app: 99450\n", stderr: "", exitCode: 0)
            default:
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
        })

        let device = try bootstrap.resolveDevice(simulatorID: "booted")
        let launch = try bootstrap.launchApp(
            request: SimulatorLaunchRequest(
                bundleIdentifier: "com.enclave.app",
                environment: [
                    "ACCESSIBILITY_PREFLIGHT_SEMANTICS": "1",
                    "ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH": "/tmp/snapshot.json"
                ]
            ),
            on: device
        )

        XCTAssertEqual(
            launchInvocation?.environment,
            [
                "SIMCTL_CHILD_ACCESSIBILITY_PREFLIGHT_SEMANTICS": "1",
                "SIMCTL_CHILD_ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH": "/tmp/snapshot.json"
            ]
        )
        XCTAssertEqual(launchInvocation?.arguments, ["simctl", "launch", "booted-device", "com.enclave.app"])
        XCTAssertEqual(launch.processIdentifier, "99450")
    }

    func testSimulatorBootstrapCanResolveAppDataContainerPath() throws {
        let deviceListJSON = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
              {
                "name": "iPhone 17",
                "udid": "booted-device",
                "state": "Booted",
                "isAvailable": true
              }
            ]
          }
        }
        """
        let bootstrap = SimulatorBootstrap(commandRunner: { invocation in
            switch invocation.arguments.joined(separator: " ") {
            case let arguments where arguments.contains("simctl list devices available -j"):
                return CommandResult(stdout: deviceListJSON, stderr: "", exitCode: 0)
            case "simctl get_app_container booted-device com.enclave.app data":
                return CommandResult(
                    stdout: "/Users/modus/Library/Developer/CoreSimulator/Devices/booted-device/data/Containers/Data/Application/app-uuid\n",
                    stderr: "",
                    exitCode: 0
                )
            default:
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
        })

        let device = try bootstrap.resolveDevice(simulatorID: "booted")
        let containerPath = try bootstrap.appDataContainerPath(bundleIdentifier: "com.enclave.app", on: device)

        XCTAssertEqual(
            containerPath,
            "/Users/modus/Library/Developer/CoreSimulator/Devices/booted-device/data/Containers/Data/Application/app-uuid"
        )
    }

    func testSimulatorBootstrapDefaultDeviceResolutionIsStable() throws {
        let deviceListJSON = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-99-1": [
              {
                "name": "iPhone 18",
                "udid": "booted-device-18",
                "state": "Booted",
                "isAvailable": true
              }
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
              {
                "name": "iPhone 17",
                "udid": "booted-device-17",
                "state": "Booted",
                "isAvailable": true
              }
            ]
          }
        }
        """
        let bootstrap = SimulatorBootstrap(commandRunner: { invocation in
            switch invocation.arguments.joined(separator: " ") {
            case let arguments where arguments.contains("simctl list devices available -j"):
                return CommandResult(stdout: deviceListJSON, stderr: "", exitCode: 0)
            default:
                return CommandResult(stdout: "", stderr: "", exitCode: 0)
            }
        })

        let first = try bootstrap.resolveDevice(simulatorID: "")
        let second = try bootstrap.resolveDevice(simulatorID: "booted")

        XCTAssertEqual(first.identifier, "booted-device-17")
        XCTAssertEqual(second.identifier, "booted-device-17")
    }

    func testRuntimeVerifierLaunchesWithSemanticEnvironmentVariables() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let launchEnvironments = LockedLaunchEnvironments()

        _ = try await IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    launchEnvironments.append(request.environment)
                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.enclave.app: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: makeStubAccessibilityAuditRunner(),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: [],
                    readingOrder: [],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            })
        ).verify(projectRoot: "/tmp/Project", simulatorID: "booted")

        let environments = launchEnvironments.values
        XCTAssertEqual(environments.count, 3)
        for environment in environments {
            XCTAssertEqual(environment["ACCESSIBILITY_PREFLIGHT_SEMANTICS"], "1")
            XCTAssertFalse(environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"]?.isEmpty ?? true)
        }
    }

    func testInstalledSemanticSnapshotAddsAppSemanticEvidence() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "HomeFrontMobile.xcodeproj",
                    projectPath: "/tmp/Project/HomeFrontMobile.xcodeproj",
                    schemeName: "HomeFrontMobile",
                    buildableName: "HomeFrontMobile.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/HomeFrontMobile.app",
                    executablePath: "/tmp/Derived/HomeFrontMobile.app/HomeFrontMobile",
                    bundleIdentifier: "com.modus.homefront",
                    scheme: "HomeFrontMobile"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    if let outputPath = request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"] {
                        let snapshot = AppSemanticSnapshot(
                            appID: "com.modus.homefront",
                            platform: "ios",
                            screenID: "dashboard",
                            selectedSection: "Dashboard",
                            primaryActions: ["Dashboard", "Protection"],
                            statusSummaries: ["Score 92", "DNS Protection On"],
                            visibleLabels: ["HomeFront", "Security score"],
                            interruptionState: "none",
                            buildScheme: "HomeFrontMobile",
                            capturedAt: ISO8601DateFormatter().date(from: "2026-04-20T12:00:00Z")!
                        )
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        try encoder.encode(snapshot).write(to: URL(fileURLWithPath: outputPath))
                    }

                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.modus.homefront: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: makeStubAccessibilityAuditRunner(),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: ["Dashboard", "Protection"],
                    readingOrder: ["Dashboard", "Protection"],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: snapshotURL.path
        )

        let semanticFinding = try XCTUnwrap(result.findings.first(where: { $0.verifiedBy == "app_semantic" }))
        XCTAssertEqual(semanticFinding.severity, .info)
        XCTAssertTrue(semanticFinding.evidence.contains("screen_id=dashboard"))
        XCTAssertTrue(semanticFinding.evidence.contains("selected_section=Dashboard"))
        XCTAssertTrue(semanticFinding.evidence.contains("snapshot_path=\(snapshotURL.path)"))
        XCTAssertTrue(result.assistedChecks.contains("Review app-declared primary actions during VoiceOver and Voice Control checks: Dashboard, Protection"))
    }

    func testDeclaredAuditScenariosProduceMultiScreenAuditMatrix() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let auditRequests = LockedLaunchEnvironments()

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "AiHD.xcodeproj",
                    projectPath: "/tmp/Project/AiHD.xcodeproj",
                    schemeName: "AiHD",
                    buildableName: "AiHD.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/AiHD.app",
                    executablePath: "/tmp/Derived/AiHD.app/AiHD",
                    bundleIdentifier: "com.modus.aihd",
                    scheme: "AiHD"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    let scenarioID = request.environment["ACCESSIBILITY_PREFLIGHT_AUDIT_SCENARIO"]
                    if let outputPath = request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"] {
                        let snapshot = AppSemanticSnapshot(
                            appID: "com.modus.aihd",
                            platform: "ios",
                            screenID: scenarioID ?? "onboarding.identityHook",
                            selectedSection: scenarioID == "settings.preferences" ? "Settings" : "Onboarding",
                            primaryActions: scenarioID == "settings.preferences" ? ["Use System", "Light", "Dark"] : ["Keep going"],
                            statusSummaries: [scenarioID ?? "default"],
                            visibleLabels: ["AiHD"],
                            elements: [],
                            auditScenarios: [
                                AppSemanticAuditScenario(
                                    scenarioID: "onboarding.identityHook",
                                    screenID: "onboarding.identityHook",
                                    label: "Onboarding"
                                ),
                                AppSemanticAuditScenario(
                                    scenarioID: "settings.preferences",
                                    screenID: "settings.preferences",
                                    label: "Settings"
                                ),
                                AppSemanticAuditScenario(
                                    scenarioID: "home.empty",
                                    screenID: "home.empty",
                                    label: "Empty Home"
                                )
                            ],
                            interruptionState: nil,
                            buildScheme: "AiHD",
                            capturedAt: ISO8601DateFormatter().date(from: "2026-04-20T12:00:00Z")!
                        )
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        try encoder.encode(snapshot).write(to: URL(fileURLWithPath: outputPath))
                    }

                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.modus.aihd: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: IOSAccessibilityAuditRunner(runRequest: { request in
                auditRequests.append(request.launchEnvironment)
                switch request.launchEnvironment["ACCESSIBILITY_PREFLIGHT_AUDIT_SCENARIO"] {
                case "settings.preferences":
                    return .completed(
                        IOSAccessibilityAuditCompleted(
                            reportPath: "/tmp/settings-audit.json",
                            issues: [
                                IOSAccessibilityAuditIssue(
                                    auditType: "contrast",
                                    compactDescription: "Settings contrast issue",
                                    detailedDescription: "Improve settings contrast.",
                                    elementDescription: nil,
                                    elementIdentifier: nil,
                                    elementLabel: nil,
                                    elementType: nil
                                )
                            ]
                        )
                    )
                case "home.empty":
                    return .completed(
                        IOSAccessibilityAuditCompleted(
                            reportPath: "/tmp/home-empty-audit.json",
                            issues: []
                        )
                    )
                default:
                    return .completed(
                        IOSAccessibilityAuditCompleted(
                            reportPath: "/tmp/default-audit.json",
                            issues: []
                        )
                    )
                }
            }),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: ["AiHD"],
                    readingOrder: ["AiHD", "Keep going"],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: snapshotURL.path
        )

        let matrixFinding = try XCTUnwrap(result.findings.first(where: {
            $0.title == "Apple accessibility audit matrix reported follow-up across 3 declared iOS screens"
        }))
        XCTAssertEqual(matrixFinding.verifiedBy, "apple_accessibility_audit_matrix")
        XCTAssertTrue(matrixFinding.evidence.contains("covered_screens=3"))
        XCTAssertTrue(matrixFinding.evidence.contains("matrix_issue_count=1"))

        XCTAssertTrue(result.assistedChecks.contains(where: {
            $0 == "Declared Apple audit matrix covered: Default launch, Empty Home, Settings."
        }))
        XCTAssertTrue(result.artifacts.contains("/tmp/default-audit.json"))
        XCTAssertTrue(result.artifacts.contains("/tmp/settings-audit.json"))
        XCTAssertTrue(result.artifacts.contains("/tmp/home-empty-audit.json"))

        let scenarioEnvironmentValues = auditRequests.values
        XCTAssertEqual(scenarioEnvironmentValues.count, 3)
        XCTAssertNil(scenarioEnvironmentValues[0]["ACCESSIBILITY_PREFLIGHT_AUDIT_SCENARIO"])
        XCTAssertEqual(scenarioEnvironmentValues[1]["ACCESSIBILITY_PREFLIGHT_AUDIT_SCENARIO"], "settings.preferences")
        XCTAssertEqual(scenarioEnvironmentValues[2]["ACCESSIBILITY_PREFLIGHT_AUDIT_SCENARIO"], "home.empty")
    }

    func testAccessibilityAuditFindingUsesSemanticElementIdentifierForSourceContext() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "HomeFrontMobile.xcodeproj",
                    projectPath: "/tmp/Project/HomeFrontMobile.xcodeproj",
                    schemeName: "HomeFrontMobile",
                    buildableName: "HomeFrontMobile.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/HomeFrontMobile.app",
                    executablePath: "/tmp/Derived/HomeFrontMobile.app/HomeFrontMobile",
                    bundleIdentifier: "com.modus.homefront",
                    scheme: "HomeFrontMobile"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    if let outputPath = request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"] {
                        let snapshot = AppSemanticSnapshot(
                            appID: "com.modus.homefront",
                            platform: "ios",
                            screenID: "dashboard",
                            selectedSection: "Dashboard",
                            primaryActions: ["Dashboard", "Protection"],
                            statusSummaries: ["Score 92"],
                            visibleLabels: ["HomeFront", "Security score"],
                            elements: [
                                AppSemanticElement(
                                    elementID: "dashboard.refresh",
                                    role: "button",
                                    label: "Refresh",
                                    accessibilityIdentifier: "dashboard.refresh.button",
                                    sourceFile: "/tmp/Project/HomeFrontMobile/Views/MainTabView.swift",
                                    sourceLine: 327
                                )
                            ],
                            interruptionState: "none",
                            buildScheme: "HomeFrontMobile",
                            capturedAt: ISO8601DateFormatter().date(from: "2026-04-20T12:00:00Z")!
                        )
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        try encoder.encode(snapshot).write(to: URL(fileURLWithPath: outputPath))
                    }

                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.modus.homefront: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: IOSAccessibilityAuditRunner(run: { _, _ in
                .completed(
                    IOSAccessibilityAuditCompleted(
                        reportPath: "/tmp/apple-audit.json",
                        issues: [
                            IOSAccessibilityAuditIssue(
                                auditType: "contrast",
                                compactDescription: "Refresh button has insufficient contrast.",
                                detailedDescription: "Improve contrast for the refresh button.",
                                elementDescription: "Refresh",
                                elementIdentifier: "dashboard.refresh.button",
                                elementLabel: "Refresh",
                                elementType: "Button"
                            )
                        ]
                    )
                )
            }),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: ["Dashboard", "Refresh"],
                    readingOrder: ["Dashboard", "Refresh"],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: snapshotURL.path
        )

        let auditFinding = try XCTUnwrap(result.findings.first(where: {
            $0.title == "Apple accessibility audit reported a contrast issue"
        }))
        XCTAssertEqual(auditFinding.file, "/tmp/Project/HomeFrontMobile/Views/MainTabView.swift")
        XCTAssertEqual(auditFinding.line, 327)
        XCTAssertTrue(auditFinding.evidence.contains("semantic_element_id=dashboard.refresh"))
        XCTAssertTrue(auditFinding.evidence.contains("semantic_match=identifier"))
    }

    func testAccessibilityAuditFindingUsesUniqueSemanticLabelWhenIdentifierIsMissing() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "HomeFrontMobile.xcodeproj",
                    projectPath: "/tmp/Project/HomeFrontMobile.xcodeproj",
                    schemeName: "HomeFrontMobile",
                    buildableName: "HomeFrontMobile.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/HomeFrontMobile.app",
                    executablePath: "/tmp/Derived/HomeFrontMobile.app/HomeFrontMobile",
                    bundleIdentifier: "com.modus.homefront",
                    scheme: "HomeFrontMobile"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    if let outputPath = request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"] {
                        let snapshot = AppSemanticSnapshot(
                            appID: "com.modus.homefront",
                            platform: "ios",
                            screenID: "dashboard",
                            selectedSection: "Dashboard",
                            primaryActions: ["Dashboard", "Protection"],
                            statusSummaries: ["Score 92"],
                            visibleLabels: ["HomeFront", "Manage Subscription"],
                            elements: [
                                AppSemanticElement(
                                    elementID: "settings.manage-subscription",
                                    role: "button",
                                    label: "Manage Subscription",
                                    accessibilityIdentifier: nil,
                                    sourceFile: "/tmp/Project/HomeFrontMobile/Views/MainTabView.swift",
                                    sourceLine: 1344
                                )
                            ],
                            interruptionState: "none",
                            buildScheme: "HomeFrontMobile",
                            capturedAt: ISO8601DateFormatter().date(from: "2026-04-20T12:00:00Z")!
                        )
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        try encoder.encode(snapshot).write(to: URL(fileURLWithPath: outputPath))
                    }

                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.modus.homefront: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: IOSAccessibilityAuditRunner(run: { _, _ in
                .completed(
                    IOSAccessibilityAuditCompleted(
                        reportPath: "/tmp/apple-audit.json",
                        issues: [
                            IOSAccessibilityAuditIssue(
                                auditType: "dynamicType",
                                compactDescription: "Manage Subscription may clip at larger text sizes.",
                                detailedDescription: "Ensure Manage Subscription can wrap and remain visible at large sizes.",
                                elementDescription: "Manage Subscription",
                                elementIdentifier: nil,
                                elementLabel: "Manage Subscription",
                                elementType: "Button"
                            )
                        ]
                    )
                )
            }),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: ["Dashboard", "Manage Subscription"],
                    readingOrder: ["Dashboard", "Manage Subscription"],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: snapshotURL.path
        )

        let auditFinding = try XCTUnwrap(result.findings.first(where: {
            $0.title == "Apple accessibility audit reported a Dynamic Type issue"
        }))
        XCTAssertEqual(auditFinding.file, "/tmp/Project/HomeFrontMobile/Views/MainTabView.swift")
        XCTAssertEqual(auditFinding.line, 1344)
        XCTAssertTrue(auditFinding.evidence.contains("semantic_element_id=settings.manage-subscription"))
        XCTAssertTrue(auditFinding.evidence.contains("semantic_match=label"))
    }

    func testAccessibilityAuditFindingUsesElementDescriptionRoleWhenXCTestStoresRawElementType() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "AiHD.xcodeproj",
                    projectPath: "/tmp/Project/AiHD.xcodeproj",
                    schemeName: "AiHD",
                    buildableName: "AiHD.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/AiHD.app",
                    executablePath: "/tmp/Derived/AiHD.app/AiHD",
                    bundleIdentifier: "com.modus.aihd",
                    scheme: "AiHD"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    if let outputPath = request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"] {
                        let snapshot = AppSemanticSnapshot(
                            appID: "com.modus.aihd",
                            platform: "ios",
                            screenID: "onboarding.identityHook",
                            selectedSection: "Onboarding",
                            primaryActions: ["Keep going"],
                            statusSummaries: ["Onboarding step 1 of 8"],
                            visibleLabels: ["AiHD", "Keep going"],
                            elements: [
                                AppSemanticElement(
                                    elementID: "onboarding.brand-pill",
                                    role: "staticText",
                                    label: "AIHD",
                                    accessibilityIdentifier: nil,
                                    sourceFile: "/tmp/Project/AiHD/AiHDApp/Sources/Features/Onboarding/OnboardingComponents.swift",
                                    sourceLine: 18
                                )
                            ],
                            interruptionState: "onboarding",
                            buildScheme: "AiHD",
                            capturedAt: ISO8601DateFormatter().date(from: "2026-04-20T12:00:00Z")!
                        )
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        try encoder.encode(snapshot).write(to: URL(fileURLWithPath: outputPath))
                    }

                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.modus.aihd: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: IOSAccessibilityAuditRunner(run: { _, _ in
                .completed(
                    IOSAccessibilityAuditCompleted(
                        reportPath: "/tmp/apple-audit.json",
                        issues: [
                            IOSAccessibilityAuditIssue(
                                auditType: "contrast",
                                compactDescription: "Brand pill has insufficient contrast.",
                                detailedDescription: "Improve contrast for the AIHD brand pill.",
                                elementDescription: "\"AIHD\" StaticText",
                                elementIdentifier: nil,
                                elementLabel: "AIHD",
                                elementType: "XCUIElementType(rawValue: 48)"
                            )
                        ]
                    )
                )
            }),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: ["AIHD", "Keep going"],
                    readingOrder: ["AIHD", "Keep going"],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: snapshotURL.path
        )

        let auditFinding = try XCTUnwrap(result.findings.first(where: {
            $0.title == "Apple accessibility audit reported a contrast issue"
        }))
        XCTAssertEqual(auditFinding.file, "/tmp/Project/AiHD/AiHDApp/Sources/Features/Onboarding/OnboardingComponents.swift")
        XCTAssertEqual(auditFinding.line, 18)
        XCTAssertTrue(auditFinding.evidence.contains("semantic_element_id=onboarding.brand-pill"))
        XCTAssertTrue(auditFinding.evidence.contains("semantic_match=label"))
    }

    func testAccessibilityAuditFindingDoesNotResolveAmbiguousSemanticLabelMatches() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "HomeFrontMobile.xcodeproj",
                    projectPath: "/tmp/Project/HomeFrontMobile.xcodeproj",
                    schemeName: "HomeFrontMobile",
                    buildableName: "HomeFrontMobile.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/HomeFrontMobile.app",
                    executablePath: "/tmp/Derived/HomeFrontMobile.app/HomeFrontMobile",
                    bundleIdentifier: "com.modus.homefront",
                    scheme: "HomeFrontMobile"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    if let outputPath = request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"] {
                        let snapshot = AppSemanticSnapshot(
                            appID: "com.modus.homefront",
                            platform: "ios",
                            screenID: "dashboard",
                            selectedSection: "Dashboard",
                            primaryActions: ["Dashboard"],
                            statusSummaries: ["Score 92"],
                            visibleLabels: ["HomeFront", "Continue"],
                            elements: [
                                AppSemanticElement(
                                    elementID: "onboarding.continue.primary",
                                    role: "button",
                                    label: "Continue",
                                    accessibilityIdentifier: nil,
                                    sourceFile: "/tmp/Project/Views/OnboardingPrimary.swift",
                                    sourceLine: 42
                                ),
                                AppSemanticElement(
                                    elementID: "onboarding.continue.secondary",
                                    role: "button",
                                    label: "Continue",
                                    accessibilityIdentifier: nil,
                                    sourceFile: "/tmp/Project/Views/OnboardingSecondary.swift",
                                    sourceLine: 88
                                )
                            ],
                            interruptionState: "none",
                            buildScheme: "HomeFrontMobile",
                            capturedAt: ISO8601DateFormatter().date(from: "2026-04-20T12:00:00Z")!
                        )
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        try encoder.encode(snapshot).write(to: URL(fileURLWithPath: outputPath))
                    }

                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.modus.homefront: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: IOSAccessibilityAuditRunner(run: { _, _ in
                .completed(
                    IOSAccessibilityAuditCompleted(
                        reportPath: "/tmp/apple-audit.json",
                        issues: [
                            IOSAccessibilityAuditIssue(
                                auditType: "contrast",
                                compactDescription: "Continue has insufficient contrast.",
                                detailedDescription: "Improve contrast for Continue.",
                                elementDescription: "Continue",
                                elementIdentifier: nil,
                                elementLabel: "Continue",
                                elementType: "Button"
                            )
                        ]
                    )
                )
            }),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: ["Continue"],
                    readingOrder: ["Continue"],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: snapshotURL.path
        )

        let auditFinding = try XCTUnwrap(result.findings.first(where: {
            $0.title == "Apple accessibility audit reported a contrast issue"
        }))
        XCTAssertNil(auditFinding.file)
        XCTAssertNil(auditFinding.line)
        XCTAssertFalse(auditFinding.evidence.contains(where: { $0.hasPrefix("semantic_match=") }))
    }

    func testAccessibilityAuditAddsCandidateSourceSummaryWhenAppleOmitsElementMetadata() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "AiHD.xcodeproj",
                    projectPath: "/tmp/Project/AiHD.xcodeproj",
                    schemeName: "AiHD",
                    buildableName: "AiHD.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/AiHD.app",
                    executablePath: "/tmp/Derived/AiHD.app/AiHD",
                    bundleIdentifier: "com.modus.aihd",
                    scheme: "AiHD"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    if let outputPath = request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"] {
                        let snapshot = AppSemanticSnapshot(
                            appID: "com.modus.aihd",
                            platform: "ios",
                            screenID: "onboarding.identityHook",
                            selectedSection: "Onboarding",
                            primaryActions: ["Keep going"],
                            statusSummaries: ["Onboarding step 1 of 8"],
                            visibleLabels: ["AiHD", "Keep going"],
                            elements: [
                                AppSemanticElement(
                                    elementID: "onboarding.title",
                                    role: "staticText",
                                    label: "This app is for messy builder brains.",
                                    accessibilityIdentifier: nil,
                                    sourceFile: "/tmp/Project/AiHD/AiHDApp/Sources/Features/Onboarding/OnboardingFlowView.swift",
                                    sourceLine: 175
                                ),
                                AppSemanticElement(
                                    elementID: "onboarding.next.label",
                                    role: "staticText",
                                    label: "Keep going",
                                    accessibilityIdentifier: nil,
                                    sourceFile: "/tmp/Project/AiHD/AiHDApp/Sources/Features/Onboarding/OnboardingComponents.swift",
                                    sourceLine: 74
                                )
                            ],
                            interruptionState: "onboarding",
                            buildScheme: "AiHD",
                            capturedAt: ISO8601DateFormatter().date(from: "2026-04-20T12:00:00Z")!
                        )
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        try encoder.encode(snapshot).write(to: URL(fileURLWithPath: outputPath))
                    }

                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.modus.aihd: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: IOSAccessibilityAuditRunner(run: { _, _ in
                .completed(
                    IOSAccessibilityAuditCompleted(
                        reportPath: "/tmp/apple-audit.json",
                        issues: [
                            IOSAccessibilityAuditIssue(
                                auditType: "elementDetection",
                                compactDescription: "Potentially inaccessible text",
                                detailedDescription: "This element appears to display text that should be represented using the accessibility API.",
                                elementDescription: nil,
                                elementIdentifier: nil,
                                elementLabel: nil,
                                elementType: nil
                            ),
                            IOSAccessibilityAuditIssue(
                                auditType: "textClipped",
                                compactDescription: "Text clipped",
                                detailedDescription: "Text of this element may be clipped at larger Dynamic Type sizes.",
                                elementDescription: nil,
                                elementIdentifier: nil,
                                elementLabel: nil,
                                elementType: nil
                            )
                        ]
                    )
                )
            }),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: ["AiHD", "Keep going"],
                    readingOrder: ["AiHD", "Keep going"],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: snapshotURL.path
        )

        let summaryFinding = try XCTUnwrap(result.findings.first(where: {
            $0.title == "Apple accessibility audit omitted element metadata for some issues"
        }))
        XCTAssertEqual(summaryFinding.confidence, Confidence.assisted)
        XCTAssertTrue(summaryFinding.evidence.contains("unmapped_issue_count=2"))
        XCTAssertTrue(summaryFinding.evidence.contains("unmapped_audit_types=elementDetection, textClipped"))
        XCTAssertTrue(summaryFinding.evidence.contains("screen_id=onboarding.identityHook"))
        XCTAssertTrue(summaryFinding.evidence.contains("candidate_source=/tmp/Project/AiHD/AiHDApp/Sources/Features/Onboarding/OnboardingComponents.swift:74"))
        XCTAssertTrue(summaryFinding.evidence.contains("candidate_source=/tmp/Project/AiHD/AiHDApp/Sources/Features/Onboarding/OnboardingFlowView.swift:175"))
    }

    func testInstalledSemanticSnapshotCopiesFromSimulatorContainerIntoRequestedHostPath() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let hostSnapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("semantic.json")
        let containerRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: containerRootURL, withIntermediateDirectories: true)

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    let outputPath = try XCTUnwrap(request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"])
                    XCTAssertTrue(outputPath.hasPrefix("/tmp/"))

                    let mirroredOutputURL = containerRootURL
                        .appendingPathComponent("tmp", isDirectory: true)
                        .appendingPathComponent(URL(fileURLWithPath: outputPath).lastPathComponent)
                    try FileManager.default.createDirectory(
                        at: mirroredOutputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    let snapshot = AppSemanticSnapshot(
                        appID: "com.enclave.app",
                        platform: "ios",
                        screenID: "webview.loaded",
                        selectedSection: nil,
                        primaryActions: [],
                        statusSummaries: ["https://localhost"],
                        visibleLabels: [],
                        interruptionState: "none",
                        buildScheme: "Enclave",
                        capturedAt: ISO8601DateFormatter().date(from: "2026-04-20T12:00:00Z")!
                    )
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    try encoder.encode(snapshot).write(to: mirroredOutputURL)

                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.enclave.app: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in },
                appDataContainerPath: { _, _ in containerRootURL.path }
            ),
            accessibilityAuditRunner: makeStubAccessibilityAuditRunner(),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: [],
                    readingOrder: [],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: hostSnapshotURL.path
        )

        let semanticFinding = try XCTUnwrap(result.findings.first(where: { $0.verifiedBy == "app_semantic" }))
        XCTAssertTrue(semanticFinding.evidence.contains("screen_id=webview.loaded"))
        XCTAssertTrue(semanticFinding.evidence.contains("snapshot_path=\(hostSnapshotURL.path)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: hostSnapshotURL.path))
    }

    func testInstalledSemanticSnapshotUsesLatestSimulatorContainerAfterAuditReinstall() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let hostSnapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("semantic.json")
        let originalContainerRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let reinstalledContainerRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: originalContainerRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reinstalledContainerRootURL, withIntermediateDirectories: true)

        var currentContainerRootURL = originalContainerRootURL
        var launchCount = 0

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    launchCount += 1
                    if launchCount == 3 {
                        let outputPath = try XCTUnwrap(request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"])
                        XCTAssertTrue(outputPath.hasPrefix("/tmp/"))

                        let mirroredOutputURL = currentContainerRootURL
                            .appendingPathComponent("tmp", isDirectory: true)
                            .appendingPathComponent(URL(fileURLWithPath: outputPath).lastPathComponent)
                        try FileManager.default.createDirectory(
                            at: mirroredOutputURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )

                        let snapshot = AppSemanticSnapshot(
                            appID: "com.enclave.app",
                            platform: "ios",
                            screenID: "reinstalled.container",
                            selectedSection: nil,
                            primaryActions: [],
                            statusSummaries: ["snapshot from reinstalled app"],
                            visibleLabels: [],
                            interruptionState: "none",
                            buildScheme: "Enclave",
                            capturedAt: ISO8601DateFormatter().date(from: "2026-04-20T12:00:00Z")!
                        )
                        let encoder = JSONEncoder()
                        encoder.dateEncodingStrategy = .iso8601
                        try encoder.encode(snapshot).write(to: mirroredOutputURL)
                    }

                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.enclave.app: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in },
                appDataContainerPath: { _, _ in currentContainerRootURL.path }
            ),
            accessibilityAuditRunner: IOSAccessibilityAuditRunner(run: { _, _ in
                currentContainerRootURL = reinstalledContainerRootURL
                return .completed(IOSAccessibilityAuditCompleted(reportPath: "/tmp/apple-audit.json", issues: []))
            }),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: [],
                    readingOrder: [],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: hostSnapshotURL.path
        )

        let semanticFinding = try XCTUnwrap(result.findings.first(where: { $0.verifiedBy == "app_semantic" }))
        XCTAssertTrue(semanticFinding.evidence.contains("screen_id=reinstalled.container"))
        XCTAssertTrue(semanticFinding.evidence.contains("snapshot_path=\(hostSnapshotURL.path)"))
        XCTAssertFalse(result.findings.contains(where: { $0.title == "Semantic snapshot could not be read" }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: hostSnapshotURL.path))
    }

    func testMissingSemanticIntegrationEmitsWarningWithoutFailingAudit() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.enclave.app: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: makeStubAccessibilityAuditRunner(),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: [],
                    readingOrder: [],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(
                    status: .missing,
                    warningText: "Semantic integration is optional and no app code was changed automatically.",
                    artifactPath: "/tmp/.accessibility-preflight/semantic-integration/enclave"
                )
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(projectRoot: "/tmp/Project", simulatorID: "booted")

        let warningFinding = try XCTUnwrap(result.findings.first(where: { $0.title.contains("semantic integration") }))
        XCTAssertEqual(warningFinding.severity, .warn)
        XCTAssertEqual(warningFinding.verifiedBy, "runtime")
        XCTAssertTrue(warningFinding.detail.contains("no app code was changed automatically"))
        XCTAssertTrue(warningFinding.evidence.contains("artifact_path=/tmp/.accessibility-preflight/semantic-integration/enclave"))
        XCTAssertFalse(result.findings.contains(where: { $0.severity == .critical }))
    }

    func testInvalidSemanticSnapshotFallsBackToOcrRuntimeFindings() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    if let outputPath = request.environment["ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH"] {
                        try "{not-json".write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
                    }

                    return SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.enclave.app: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: makeStubAccessibilityAuditRunner(),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, label in
                if label == "default" {
                    return SimulatorScreenInspectionResult(
                        screenshotPath: "/tmp/default.png",
                        recognizedTexts: ["Continue", "Continue"],
                        readingOrder: ["Continue", "Continue"],
                        duplicateCommandNames: ["Continue"],
                        truncationCandidates: [],
                        crowdedTextPairs: []
                    )
                }

                return SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/dynamic.png",
                    recognizedTexts: [],
                    readingOrder: [],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: snapshotURL.path
        )

        XCTAssertNotNil(result.findings.first(where: { $0.title == "Visible command names may be ambiguous for Voice Control" }))
        XCTAssertFalse(result.findings.contains(where: { $0.verifiedBy == "app_semantic" }))
        let warningFinding = try XCTUnwrap(result.findings.first(where: { $0.title == "Semantic snapshot could not be read" }))
        XCTAssertEqual(warningFinding.severity, .warn)
        XCTAssertTrue(warningFinding.evidence.contains("snapshot_path=\(snapshotURL.path)"))
        XCTAssertTrue(warningFinding.evidence.contains(where: { $0.hasPrefix("reason=") }))
    }

    func testMissingInstalledSemanticSnapshotEmitsWarningAndPreservesFallback() async throws {
        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.enclave.app: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: makeStubAccessibilityAuditRunner(),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: ["Continue", "Continue"],
                    readingOrder: ["Continue", "Continue"],
                    duplicateCommandNames: ["Continue"],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                SemanticIntegrationAdvice(status: .installed, warningText: "", artifactPath: nil)
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(
            projectRoot: "/tmp/Project",
            simulatorID: "booted",
            semanticSnapshotOverridePath: snapshotURL.path
        )

        XCTAssertNotNil(result.findings.first(where: { $0.title == "Visible command names may be ambiguous for Voice Control" }))
        let warningFinding = try XCTUnwrap(result.findings.first(where: { $0.title == "Semantic snapshot could not be read" }))
        XCTAssertEqual(warningFinding.severity, .warn)
        XCTAssertTrue(warningFinding.evidence.contains("snapshot_path=\(snapshotURL.path)"))
        XCTAssertTrue(warningFinding.evidence.contains(where: { $0.contains("No such file") || $0.contains("couldn’t be opened") || $0.contains("cannot be opened") }))
    }

    func testSemanticIntegrationAdvisorFailureEmitsWarningWithoutBlockingAudit() async throws {
        struct AdvisorFailure: LocalizedError {
            var errorDescription: String? { "artifact generation failed" }
        }

        let device = SimulatorDevice(identifier: "booted-device", name: "iPhone 17", wasBooted: true)
        let verifier = IOSRuntimeVerifier(
            targetResolver: { _ in
                ResolvedBuildTarget(
                    projectName: "Enclave.xcodeproj",
                    projectPath: "/tmp/Project/Enclave.xcodeproj",
                    schemeName: "Enclave",
                    buildableName: "Enclave.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/Enclave.app",
                    executablePath: "/tmp/Derived/Enclave.app/Enclave",
                    bundleIdentifier: "com.enclave.app",
                    scheme: "Enclave"
                )
            },
            simulatorBootstrap: SimulatorBootstrap(
                resolveDevice: { _ in device },
                uninstallApp: { _, _ in },
                installApp: { _, _ in },
                terminateApp: { _, _ in },
                launchApp: { request, resolvedDevice in
                    SimulatorLaunchResult(
                        device: resolvedDevice,
                        bundleIdentifier: request.bundleIdentifier,
                        processIdentifier: "123",
                        launchOutput: "com.enclave.app: 123"
                    )
                },
                contentSizeCategory: { _ in "large" },
                setContentSizeCategory: { _, _ in }
            ),
            accessibilityAuditRunner: makeStubAccessibilityAuditRunner(),
            dynamicTypePass: .init(),
            screenInspector: SimulatorScreenInspector(inspect: { _, _ in
                SimulatorScreenInspectionResult(
                    screenshotPath: "/tmp/default.png",
                    recognizedTexts: [],
                    readingOrder: [],
                    duplicateCommandNames: [],
                    truncationCandidates: [],
                    crowdedTextPairs: []
                )
            }),
            semanticIntegrationAdvisor: { _, _, _ in
                throw AdvisorFailure()
            },
            semanticSnapshotReader: SemanticSnapshotReader()
        )

        let result = try await verifier.verify(projectRoot: "/tmp/Project", simulatorID: "booted")

        let warningFinding = try XCTUnwrap(result.findings.first(where: { $0.title == "Semantic integration advice could not be generated" }))
        XCTAssertEqual(warningFinding.severity, .warn)
        XCTAssertTrue(warningFinding.evidence.contains("reason=artifact generation failed"))
        XCTAssertFalse(result.findings.contains(where: { $0.severity == .critical }))
    }
}

private final class LockedCallLog {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func count(matchingPrefix prefix: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.filter { $0.hasPrefix(prefix) }.count
    }
}

private final class LockedLaunchEnvironments {
    private let lock = NSLock()
    private var storage: [[String: String]] = []

    func append(_ value: [String: String]) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private func writeSemanticSnapshot(screenID: String, to url: URL) throws {
    let snapshot = AppSemanticSnapshot(
        appID: "com.example.demo",
        platform: "ios",
        screenID: screenID,
        selectedSection: "Test",
        primaryActions: ["Continue"],
        statusSummaries: ["Ready"],
        visibleLabels: ["Demo"],
        interruptionState: nil,
        buildScheme: "Demo",
        capturedAt: Date(timeIntervalSince1970: 1_713_571_200)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(snapshot).write(to: url)
}

private func makeStubAccessibilityAuditRunner() -> IOSAccessibilityAuditRunner {
    IOSAccessibilityAuditRunner(run: { _, _ in
        .completed(IOSAccessibilityAuditCompleted(reportPath: "/tmp/apple-audit.json", issues: []))
    })
}
