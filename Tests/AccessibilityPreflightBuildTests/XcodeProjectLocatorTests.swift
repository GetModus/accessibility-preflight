import XCTest
@testable import AccessibilityPreflightBuild

final class XcodeProjectLocatorTests: XCTestCase {
    func testLocatesXcodeProjectName() throws {
        let root = try makeTemporaryProjectDirectory()
        let project = try XcodeProjectLocator.locateProject(in: root.path)
        XCTAssertEqual(project, "MyApp.xcodeproj")
    }

    func testResolveBuildTargetPrefersExplicitSchemeOrBuildableName() throws {
        let root = try makeTemporaryProjectDirectory()
        let schemesRoot = root
            .appendingPathComponent("MyApp.xcodeproj", isDirectory: true)
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("xcschemes", isDirectory: true)
        try FileManager.default.createDirectory(at: schemesRoot, withIntermediateDirectories: true, attributes: nil)

        try """
        BuildableName = "Alpha.app"
        """.write(
            to: schemesRoot.appendingPathComponent("AlphaScheme.xcscheme"),
            atomically: true,
            encoding: .utf8
        )
        try """
        BuildableName = "Beta.app"
        """.write(
            to: schemesRoot.appendingPathComponent("BetaScheme.xcscheme"),
            atomically: true,
            encoding: .utf8
        )

        let result = try XcodeProjectLocator.resolveBuildTarget(in: root.path, preferringScheme: "Beta")

        XCTAssertEqual(result.schemeName, "BetaScheme")
        XCTAssertEqual(result.buildableName, "Beta.app")
    }

    func testResolveBuildTargetUsesWorkspaceContainerWhenAvailable() throws {
        let root = try makeTemporaryProjectDirectory()
        let workspace = root.appendingPathComponent("MyApp.xcworkspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: nil)

        let result = try XcodeProjectLocator.resolveBuildTarget(
            in: root.path,
            preferringScheme: nil,
            commandRunner: { invocation in
                XCTAssertEqual(
                    invocation.arguments,
                    ["-workspace", workspace.path, "-list", "-json"]
                )
                return CommandResult(
                    stdout: """
                    {
                      "workspace" : {
                        "name" : "MyApp",
                        "schemes" : ["WorkspaceApp"]
                      }
                    }
                    """,
                    stderr: "",
                    exitCode: 0
                )
            }
        )

        XCTAssertEqual(result.containerKind, .workspace)
        XCTAssertEqual(result.containerName, "MyApp.xcworkspace")
        XCTAssertEqual(result.containerPath, workspace.path)
        XCTAssertEqual(result.schemeName, "WorkspaceApp")
    }

    func testResolveBuildTargetFallsBackToXcodebuildProjectSchemeListing() throws {
        let root = try makeTemporaryProjectDirectory()

        let result = try XcodeProjectLocator.resolveBuildTarget(
            in: root.path,
            preferringScheme: nil,
            commandRunner: { invocation in
                XCTAssertEqual(
                    invocation.arguments,
                    ["-project", root.appendingPathComponent("MyApp.xcodeproj").path, "-list", "-json"]
                )
                return CommandResult(
                    stdout: """
                    {
                      "project" : {
                        "name" : "MyApp",
                        "schemes" : ["ProjectApp"]
                      }
                    }
                    """,
                    stderr: "",
                    exitCode: 0
                )
            }
        )

        XCTAssertEqual(result.containerKind, .project)
        XCTAssertEqual(result.schemeName, "ProjectApp")
    }

    private func makeTemporaryProjectDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = root.appendingPathComponent("MyApp.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)
        return root
    }
}
