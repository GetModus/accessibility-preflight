import XCTest
@testable import AccessibilityPreflightCore

final class ProjectDiscoveryTests: XCTestCase {
    func testDiscoversXcodeProjectAndPlatform() throws {
        let root = try makeTemporaryProjectDirectory()
        let result = try ProjectDiscovery.discover(in: root.path)
        XCTAssertEqual(result.platform, "ios")
        XCTAssertEqual(result.projectName, "MyApp.xcodeproj")
    }

    func testInfersMacPlatformFromPathComponent() throws {
        let root = try makeTemporaryProjectDirectory(nestedIn: "macos")
        let result = try ProjectDiscovery.discover(in: root.path)
        XCTAssertEqual(result.platform, "macos")
    }

    func testInfersMacPlatformFromProjectBuildSettings() throws {
        let root = try makeTemporaryProjectDirectory()
        let pbxproj = root.appendingPathComponent("MyApp.xcodeproj/project.pbxproj")
        try """
        buildSettings = {
            SDKROOT = macosx;
            SUPPORTED_PLATFORMS = macosx;
        };
        """.write(to: pbxproj, atomically: true, encoding: .utf8)

        let result = try ProjectDiscovery.discover(in: root.path)

        XCTAssertEqual(result.platform, "macos")
    }

    func testChoosesProjectsDeterministicallyWhenMultipleProjectsExist() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("BApp.xcodeproj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("AApp.xcodeproj"), withIntermediateDirectories: true)

        XCTAssertEqual(try ProjectDiscovery.xcodeProjectName(in: root.path), "AApp.xcodeproj")
    }

    func testPrefersWorkspaceContainerWhenWorkspaceExistsAtRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("MyApp.xcodeproj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("MyApp.xcworkspace"), withIntermediateDirectories: true)

        let result = try ProjectDiscovery.discover(in: root.path)

        XCTAssertEqual(result.containerKind, .workspace)
        XCTAssertEqual(result.containerName, "MyApp.xcworkspace")
        XCTAssertEqual(result.containerPath, root.appendingPathComponent("MyApp.xcworkspace").path)
        XCTAssertEqual(result.projectName, "MyApp.xcodeproj")
    }

    private func makeTemporaryProjectDirectory(nestedIn component: String? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let projectRoot = component.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        let project = projectRoot.appendingPathComponent("MyApp.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)
        return projectRoot
    }
}
