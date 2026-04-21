import XCTest
@testable import AccessibilityPreflightCore

final class PreflightRunnerTests: XCTestCase {
    func testRunsStaticThenMacRuntimeForMacProjects() async throws {
        let root = try makeTemporaryProjectDirectory(nestedIn: "macos")
        let callLog = LockedCallLog()

        let runner = PreflightRunner(
            dependencies: PreflightDependencies(
                staticScan: { project in
                    callLog.append("static:\(project.platform)")
                    return PreflightSliceResult(
                        findings: [
                            Finding(
                                platform: "shared",
                                surface: "static",
                                severity: .warn,
                                confidence: .heuristic,
                                title: "Static finding",
                                detail: "Static detail",
                                fix: "Static fix",
                                evidence: ["static"],
                                file: project.rootPath,
                                line: nil,
                                verifiedBy: "static"
                            )
                        ],
                        assistedChecks: ["static check"]
                    )
                },
                iosRuntime: { project in
                    callLog.append("ios:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["ios runtime"])
                },
                macRuntime: { project in
                    callLog.append("mac:\(project.platform)")
                    return PreflightSliceResult(
                        findings: [
                            Finding(
                                platform: "macos",
                                surface: "runtime",
                                severity: .critical,
                                confidence: .proven,
                                title: "Runtime finding",
                                detail: "Runtime detail",
                                fix: "Runtime fix",
                                evidence: ["runtime"],
                                file: project.rootPath,
                                line: 12,
                                verifiedBy: "runtime"
                            )
                        ],
                        assistedChecks: ["mac runtime"]
                    )
                }
            )
        )

        let result = try await runner.run(path: root.path, command: .preflight)

        XCTAssertEqual(callLog.values, ["static:macos", "mac:macos"])
        XCTAssertEqual(result.findings.count, 2)
        XCTAssertEqual(result.findings.map(\.verifiedBy), ["static", "runtime"])
        XCTAssertTrue(result.assistedChecks.contains("static check"))
        XCTAssertTrue(result.assistedChecks.contains("mac runtime"))
    }

    func testRunsIosRuntimeForIosProjects() async throws {
        let root = try makeTemporaryProjectDirectory()
        let callLog = LockedCallLog()

        let runner = PreflightRunner(
            dependencies: PreflightDependencies(
                staticScan: { project in
                    callLog.append("static:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: [])
                },
                iosRuntime: { project in
                    callLog.append("ios:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["ios runtime"])
                },
                macRuntime: { project in
                    callLog.append("mac:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["mac runtime"])
                }
            )
        )

        _ = try await runner.run(path: root.path, command: .preflight)

        XCTAssertEqual(callLog.values, ["static:ios", "ios:ios"])
    }

    func testStaticCommandSkipsRuntime() async throws {
        let root = try makeTemporaryProjectDirectory()
        let callLog = LockedCallLog()

        let runner = PreflightRunner(
            dependencies: PreflightDependencies(
                staticScan: { project in
                    callLog.append("static:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["static"])
                },
                iosRuntime: { project in
                    callLog.append("ios:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["ios"])
                },
                macRuntime: { project in
                    callLog.append("mac:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["mac"])
                }
            )
        )

        let result = try await runner.run(path: root.path, command: .static)

        XCTAssertEqual(callLog.values, ["static:ios"])
        XCTAssertEqual(result.assistedChecks, ["static"])
    }

    func testIosRunCommandRunsOnlyIosRuntime() async throws {
        let root = try makeTemporaryProjectDirectory()
        let callLog = LockedCallLog()

        let runner = PreflightRunner(
            dependencies: PreflightDependencies(
                staticScan: { project in
                    callLog.append("static:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["static"])
                },
                iosRuntime: { project in
                    callLog.append("ios:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["ios"])
                },
                macRuntime: { project in
                    callLog.append("mac:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["mac"])
                }
            )
        )

        let result = try await runner.run(path: root.path, command: .iosRun)

        XCTAssertEqual(callLog.values, ["ios:ios"])
        XCTAssertEqual(result.assistedChecks, ["ios"])
    }

    func testMacosRunCommandRunsOnlyMacRuntime() async throws {
        let root = try makeTemporaryProjectDirectory(nestedIn: "macos")
        let callLog = LockedCallLog()

        let runner = PreflightRunner(
            dependencies: PreflightDependencies(
                staticScan: { project in
                    callLog.append("static:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["static"])
                },
                iosRuntime: { project in
                    callLog.append("ios:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["ios"])
                },
                macRuntime: { project in
                    callLog.append("mac:\(project.platform)")
                    return PreflightSliceResult(findings: [], assistedChecks: ["mac"])
                }
            )
        )

        let result = try await runner.run(path: root.path, command: .macosRun)

        XCTAssertEqual(callLog.values, ["mac:macos"])
        XCTAssertEqual(result.assistedChecks, ["mac"])
    }

    private func makeTemporaryProjectDirectory(nestedIn component: String? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projectRoot = component.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true, attributes: nil)
        let project = projectRoot.appendingPathComponent("MyApp.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)
        try "import Foundation\nprint(\"Hello\")\n".write(to: projectRoot.appendingPathComponent("ContentView.swift"), atomically: true, encoding: .utf8)
        return projectRoot
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
}
