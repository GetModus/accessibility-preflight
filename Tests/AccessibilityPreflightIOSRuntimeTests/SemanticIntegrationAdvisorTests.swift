import XCTest
@testable import AccessibilityPreflightIOSRuntime

final class SemanticIntegrationAdvisorTests: XCTestCase {
    func testMissingIntegrationGeneratesStandaloneArtifactOutsideAppSourceTree() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        let projectRoot = root.appendingPathComponent("Project", isDirectory: true)
        let appRoot = projectRoot.appendingPathComponent("Apps/Enclave/iOS", isDirectory: true)
        try fileManager.createDirectory(at: appRoot, withIntermediateDirectories: true)

        let advisor = SemanticIntegrationAdvisor(fileManager: fileManager)
        let advice = try advisor.advise(projectRoot: projectRoot.path, appRoot: appRoot.path, appSlug: "enclave")

        XCTAssertEqual(advice.status, .missing)
        XCTAssertTrue(advice.warningText.contains("no app code was changed automatically"))

        let artifactDirectory = try XCTUnwrap(advice.artifactPath)
        XCTAssertTrue(artifactDirectory.hasPrefix(projectRoot.path))
        XCTAssertTrue(artifactDirectory.contains(".accessibility-preflight/semantic-integration/enclave"))
        XCTAssertFalse(artifactDirectory.hasPrefix(appRoot.path))

        let readmePath = URL(fileURLWithPath: artifactDirectory).appendingPathComponent("README.md").path
        let exportPath = URL(fileURLWithPath: artifactDirectory).appendingPathComponent("AccessibilityPreflightSemanticExport.swift").path
        XCTAssertTrue(fileManager.fileExists(atPath: readmePath))
        XCTAssertTrue(fileManager.fileExists(atPath: exportPath))

        let readmeContents = try String(contentsOfFile: readmePath, encoding: .utf8)
        let exportContents = try String(contentsOfFile: exportPath, encoding: .utf8)
        XCTAssertTrue(readmeContents.contains("proposed and not applied"))
        XCTAssertTrue(readmeContents.contains("review and apply after approval"))
        XCTAssertTrue(exportContents.contains("AccessibilityPreflightSemanticElement"))
        XCTAssertTrue(exportContents.contains("sourceFile"))
        XCTAssertTrue(exportContents.contains("recordElement"))
    }

    func testInstalledIntegrationIsDetectedWhenSemanticExportAlreadyExists() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        let projectRoot = root.appendingPathComponent("Project", isDirectory: true)
        let appRoot = projectRoot.appendingPathComponent("Apps/HomeFront/HomeFrontMobile", isDirectory: true)
        let integrationFile = appRoot.appendingPathComponent("HomeFrontMobile/AccessibilityPreflightSemanticExport.swift")
        try fileManager.createDirectory(at: integrationFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try adoptedSemanticExportContents().write(to: integrationFile, atomically: true, encoding: .utf8)

        let advisor = SemanticIntegrationAdvisor(fileManager: fileManager)
        let advice = try advisor.advise(projectRoot: projectRoot.path, appRoot: appRoot.path, appSlug: "homefront")

        XCTAssertEqual(advice.status, .installed)
        XCTAssertNil(advice.artifactPath)
        XCTAssertTrue(advice.warningText.contains("no app code was changed automatically"))
    }

    func testInstalledIntegrationIsDetectedWhenSemanticExportLivesInsideSourcesTree() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        let projectRoot = root.appendingPathComponent("Project", isDirectory: true)
        let appRoot = projectRoot.appendingPathComponent("Apps/AiHD", isDirectory: true)
        let integrationFile = appRoot
            .appendingPathComponent("AiHDApp", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("AccessibilityPreflightSemanticExport.swift")
        try fileManager.createDirectory(at: integrationFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try adoptedSemanticExportContents().write(to: integrationFile, atomically: true, encoding: .utf8)

        let advisor = SemanticIntegrationAdvisor(fileManager: fileManager)
        let advice = try advisor.advise(projectRoot: projectRoot.path, appRoot: appRoot.path, appSlug: "aihd")

        XCTAssertEqual(advice.status, .installed)
        XCTAssertNil(advice.artifactPath)
    }

    func testArbitraryNestedFileDoesNotCountAsInstalled() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        let projectRoot = root.appendingPathComponent("Project", isDirectory: true)
        let appRoot = projectRoot.appendingPathComponent("Apps/Enclave/iOS", isDirectory: true)
        let falsePositiveFile = appRoot.appendingPathComponent("Some/Deep/Folder/AccessibilityPreflightSemanticExport.swift")
        try fileManager.createDirectory(at: falsePositiveFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try semanticExportContents(appSlug: "enclave").write(to: falsePositiveFile, atomically: true, encoding: .utf8)

        let advisor = SemanticIntegrationAdvisor(fileManager: fileManager)
        let advice = try advisor.advise(projectRoot: projectRoot.path, appRoot: appRoot.path, appSlug: "enclave")

        XCTAssertEqual(advice.status, .missing)
        XCTAssertNotNil(advice.artifactPath)
    }

    func testDeclarationShapedCommentOrStringDoesNotCountAsInstalled() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        let projectRoot = root.appendingPathComponent("Project", isDirectory: true)
        let appRoot = projectRoot.appendingPathComponent("Apps/Enclave/iOS", isDirectory: true)
        let falsePositiveFile = appRoot.appendingPathComponent("AccessibilityPreflightSemanticExport.swift")
        try fileManager.createDirectory(at: falsePositiveFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        import Foundation

        // public enum AccessibilityPreflightSemanticExport { }
        let name = "public enum AccessibilityPreflightSemanticExport { }"
        let value = 1
        """.write(to: falsePositiveFile, atomically: true, encoding: .utf8)

        let advisor = SemanticIntegrationAdvisor(fileManager: fileManager)
        let advice = try advisor.advise(projectRoot: projectRoot.path, appRoot: appRoot.path, appSlug: "enclave")

        XCTAssertEqual(advice.status, .missing)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func semanticExportContents(appSlug: String) -> String {
        """
        import Foundation

        // Warning: proposed and not applied.
        // This semantic export is generated for review only and does not modify app source automatically.
        //
        // App slug: \(appSlug)

        public enum AccessibilityPreflightSemanticExport {
            public static let reviewStatus = "proposed and not applied"
            public static let reviewInstruction = "review and apply after approval."
        }
        """
    }

    private func adoptedSemanticExportContents() -> String {
        """
        import Foundation

        public enum AccessibilityPreflightSemanticExport {
            public static func exportSummary() -> String {
                "Semantic export is active."
            }

            public static func reviewNote(for appName: String) -> String {
                "Semantic export is active for \\(appName)."
            }
        }
        """
    }
}
