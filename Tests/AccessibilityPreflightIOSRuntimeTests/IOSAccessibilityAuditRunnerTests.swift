import XCTest
@testable import AccessibilityPreflightIOSRuntime
import AccessibilityPreflightBuild

final class IOSAccessibilityAuditRunnerTests: XCTestCase {
    func testCopiedProjectAuditBuildIsCachedAcrossRuns() throws {
        let fileManager = FileManager.default
        let workspaceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ios-audit-runner-tests-\(UUID().uuidString)", isDirectory: true)
        let appsRoot = workspaceRoot.appendingPathComponent("apps", isDirectory: true)
        let projectRoot = appsRoot.appendingPathComponent("DemoApp", isDirectory: true)
        let projectPath = projectRoot.appendingPathComponent("DemoApp.xcodeproj")

        try fileManager.createDirectory(at: projectPath, withIntermediateDirectories: true)
        try "name: DemoApp\n".write(
            to: projectRoot.appendingPathComponent("project.yml"),
            atomically: true,
            encoding: .utf8
        )

        var invocations: [CommandInvocation] = []
        let device = SimulatorDevice(
            identifier: "SIM-123",
            name: "iPhone Test",
            wasBooted: true
        )

        let runner = IOSAccessibilityAuditRunner(
            commandRunner: { invocation in
                invocations.append(invocation)
                if invocation.executable.contains("xcodegen") {
                    return CommandResult(stdout: "", stderr: "", exitCode: 0)
                }

                if invocation.arguments.contains("build-for-testing") {
                    let derivedDataIndex = try XCTUnwrap(invocation.arguments.firstIndex(of: "-derivedDataPath"))
                    let derivedDataPath = invocation.arguments[derivedDataIndex + 1]
                    let xctestRunURL = URL(fileURLWithPath: derivedDataPath, isDirectory: true)
                        .appendingPathComponent("Build/Products/Debug-iphonesimulator/DemoHarness.xctestrun")
                    try fileManager.createDirectory(
                        at: xctestRunURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let plist: [String: Any] = [
                        "__xctestrun_metadata__": [:],
                        "AccessibilityAuditHarnessUITests": [:]
                    ]
                    let plistData = try PropertyListSerialization.data(
                        fromPropertyList: plist,
                        format: .xml,
                        options: 0
                    )
                    try plistData.write(to: xctestRunURL)
                    return CommandResult(stdout: "", stderr: "", exitCode: 0)
                }

                if invocation.arguments.contains("test-without-building") {
                    let xctestRunIndex = try XCTUnwrap(invocation.arguments.firstIndex(of: "-xctestrun"))
                    let patchedRunPath = invocation.arguments[xctestRunIndex + 1]
                    let patchedRunData = try Data(contentsOf: URL(fileURLWithPath: patchedRunPath))
                    let patchedRun = try XCTUnwrap(
                        PropertyListSerialization.propertyList(
                            from: patchedRunData,
                            options: [],
                            format: nil
                        ) as? [String: Any]
                    )
                    let target = try XCTUnwrap(
                        patchedRun["AccessibilityAuditHarnessUITests"] as? [String: Any]
                    )
                    let appEnvironment = try XCTUnwrap(
                        target["UITargetAppEnvironmentVariables"] as? [String: String]
                    )
                    let scenarioID = appEnvironment["ACCESSIBILITY_PREFLIGHT_AUDIT_SCENARIO"] ?? "default"

                    let copiedProjectRoot = try XCTUnwrap(invocation.workingDirectory)
                    let reportURL = URL(fileURLWithPath: copiedProjectRoot, isDirectory: true)
                        .deletingLastPathComponent()
                        .deletingLastPathComponent()
                        .appendingPathComponent("audit-report.json")
                    try fileManager.createDirectory(
                        at: reportURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let reportData = """
                    {
                      "bundle_identifier" : "com.example.demo",
                      "issues" : [
                        {
                          "auditType" : "trait",
                          "compactDescription" : "\(scenarioID)",
                          "detailedDescription" : "Scenario \(scenarioID)",
                          "elementDescription" : null,
                          "elementIdentifier" : null,
                          "elementLabel" : null,
                          "elementType" : null
                        }
                      ]
                    }
                    """.data(using: .utf8)
                    try XCTUnwrap(reportData).write(to: reportURL)
                    return CommandResult(stdout: "", stderr: "", exitCode: 0)
                }

                XCTFail("Unexpected invocation: \(invocation)")
                return CommandResult(stdout: "", stderr: "", exitCode: 1)
            },
            fileManager: fileManager
        )

        let defaultResult = runner.run(
            bundleIdentifier: "com.example.demo",
            launchEnvironment: [:],
            containerKind: .project,
            containerName: "DemoApp",
            containerPath: projectPath.path,
            projectPath: projectPath.path,
            targetName: "DemoApp",
            on: device
        )
        let settingsResult = runner.run(
            bundleIdentifier: "com.example.demo",
            launchEnvironment: [
                "ACCESSIBILITY_PREFLIGHT_AUDIT_SCENARIO": "settings.preferences"
            ],
            containerKind: .project,
            containerName: "DemoApp",
            containerPath: projectPath.path,
            projectPath: projectPath.path,
            targetName: "DemoApp",
            on: device
        )

        let generateCount = invocations.filter {
            $0.executable.contains("xcodegen")
        }.count
        XCTAssertEqual(generateCount, 1)

        let buildCount = invocations.filter {
            $0.arguments.contains("build-for-testing")
        }.count
        XCTAssertEqual(buildCount, 1)

        let testCount = invocations.filter {
            $0.arguments.contains("test-without-building")
        }.count
        XCTAssertEqual(testCount, 2)

        guard
            case .completed(let defaultCompleted) = defaultResult,
            case .completed(let settingsCompleted) = settingsResult
        else {
            return XCTFail("Expected both copied-project audits to complete.")
        }

        XCTAssertNotEqual(defaultCompleted.reportPath, settingsCompleted.reportPath)
        XCTAssertTrue(fileManager.fileExists(atPath: defaultCompleted.reportPath))
        XCTAssertTrue(fileManager.fileExists(atPath: settingsCompleted.reportPath))
        XCTAssertTrue(defaultCompleted.reportPath.contains("audit-report-default"))
        XCTAssertTrue(settingsCompleted.reportPath.contains("audit-report-settings-preferences"))
        XCTAssertEqual(defaultCompleted.issues.first?.compactDescription, "default")
        XCTAssertEqual(settingsCompleted.issues.first?.compactDescription, "settings.preferences")
    }
}
