import Foundation
import AccessibilityPreflightBuild
import AccessibilityPreflightCore

public struct IOSAccessibilityAuditIssue: Codable, Equatable, Sendable {
    public let auditType: String
    public let compactDescription: String
    public let detailedDescription: String
    public let elementDescription: String?
    public let elementIdentifier: String?
    public let elementLabel: String?
    public let elementType: String?

    public init(
        auditType: String,
        compactDescription: String,
        detailedDescription: String,
        elementDescription: String?,
        elementIdentifier: String?,
        elementLabel: String?,
        elementType: String?
    ) {
        self.auditType = auditType
        self.compactDescription = compactDescription
        self.detailedDescription = detailedDescription
        self.elementDescription = elementDescription
        self.elementIdentifier = elementIdentifier
        self.elementLabel = elementLabel
        self.elementType = elementType
    }
}

public struct IOSAccessibilityAuditCompleted: Codable, Equatable, Sendable {
    public let reportPath: String
    public let issues: [IOSAccessibilityAuditIssue]

    public init(reportPath: String, issues: [IOSAccessibilityAuditIssue]) {
        self.reportPath = reportPath
        self.issues = issues
    }
}

public enum IOSAccessibilityAuditExecutionResult: Equatable, Sendable {
    case completed(IOSAccessibilityAuditCompleted)
    case skipped(reason: String)
}

public enum IOSAccessibilityAuditRunnerError: LocalizedError {
    case missingXcodeGen
    case missingHarnessTemplate(String)
    case generationFailed(String)
    case missingXCTestRun(String)
    case simulatorAppPathUnavailable(String)
    case testFailed(String)
    case missingReport(String)

    public var errorDescription: String? {
        switch self {
        case .missingXcodeGen:
            return "xcodegen is required to generate the iOS accessibility audit harness."
        case .missingHarnessTemplate(let path):
            return "The iOS accessibility audit harness template was not found at \(path)."
        case .generationFailed(let detail):
            return "Failed to generate the iOS accessibility audit harness: \(detail)"
        case .missingXCTestRun(let path):
            return "The iOS accessibility audit harness did not produce an .xctestrun file under \(path)."
        case .simulatorAppPathUnavailable(let detail):
            return "The iOS accessibility audit harness could not resolve the installed simulator app path: \(detail)"
        case .testFailed(let detail):
            return "The iOS accessibility audit harness failed to run: \(detail)"
        case .missingReport(let path):
            return "The iOS accessibility audit harness did not produce a report at \(path)."
        }
    }
}

public struct IOSAccessibilityAuditRunner {
    public struct IOSAccessibilityAuditRequest {
        public let bundleIdentifier: String
        public let appPath: String?
        public let launchEnvironment: [String: String]
        public let containerKind: XcodeContainerKind?
        public let containerName: String?
        public let containerPath: String?
        public let projectPath: String?
        public let targetName: String
        public let device: SimulatorDevice

        public init(
            bundleIdentifier: String,
            appPath: String? = nil,
            launchEnvironment: [String: String] = [:],
            containerKind: XcodeContainerKind? = nil,
            containerName: String? = nil,
            containerPath: String? = nil,
            projectPath: String? = nil,
            targetName: String,
            device: SimulatorDevice
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.appPath = appPath
            self.launchEnvironment = launchEnvironment
            self.containerKind = containerKind
            self.containerName = containerName
            self.containerPath = containerPath
            self.projectPath = projectPath
            self.targetName = targetName
            self.device = device
        }
    }

    private let runHandler: (IOSAccessibilityAuditRequest) throws -> IOSAccessibilityAuditExecutionResult

    public init(
        commandRunner: @escaping (CommandInvocation) throws -> CommandResult = ProcessCommandRunner.run,
        fileManager: FileManager = .default
    ) {
        let copiedProjectCache = CopiedProjectAuditWorkspaceCache()
        self.runHandler = { request in
            do {
                return try Self.runAudit(
                    request: request,
                    copiedProjectCache: copiedProjectCache,
                    commandRunner: commandRunner,
                    fileManager: fileManager
                )
            } catch {
                return .skipped(reason: error.localizedDescription)
            }
        }
    }

    public init(
        run: @escaping (String, SimulatorDevice) throws -> IOSAccessibilityAuditExecutionResult
    ) {
        self.runHandler = { request in
            try run(request.bundleIdentifier, request.device)
        }
    }

    public init(
        runRequest: @escaping (IOSAccessibilityAuditRequest) throws -> IOSAccessibilityAuditExecutionResult
    ) {
        self.runHandler = runRequest
    }

    public func run(
        bundleIdentifier: String,
        appPath: String? = nil,
        launchEnvironment: [String: String] = [:],
        containerKind: XcodeContainerKind? = nil,
        containerName: String? = nil,
        containerPath: String? = nil,
        projectPath: String? = nil,
        targetName: String,
        on device: SimulatorDevice
    ) -> IOSAccessibilityAuditExecutionResult {
        do {
            return try runHandler(
                IOSAccessibilityAuditRequest(
                    bundleIdentifier: bundleIdentifier,
                    appPath: appPath,
                    launchEnvironment: launchEnvironment,
                    containerKind: containerKind,
                    containerName: containerName,
                    containerPath: containerPath,
                    projectPath: projectPath,
                    targetName: targetName,
                    device: device
                )
            )
        } catch {
            return .skipped(reason: error.localizedDescription)
        }
    }
}

private extension IOSAccessibilityAuditRunner {
    static let harnessSchemeName = "AccessibilityAuditHarness"
    static let harnessTargetName = "AccessibilityAuditHarnessUITests"
    static let overlaySpecFilename = "accessibility-audit-overlay.yml"
    static let baseSpecFilename = "project.base.yml"

    struct HarnessReport: Codable, Equatable {
        let bundleIdentifier: String
        let issues: [IOSAccessibilityAuditIssue]

        private enum CodingKeys: String, CodingKey {
            case bundleIdentifier = "bundle_identifier"
            case issues
        }
    }

    final class CopiedProjectAuditWorkspaceCache {
        private let lock = NSLock()
        private var workspaces: [String: CopiedProjectAuditWorkspace] = [:]

        func workspace(
            for key: String,
            create: () throws -> CopiedProjectAuditWorkspace
        ) throws -> CopiedProjectAuditWorkspace {
            lock.lock()
            if let cached = workspaces[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let preparedWorkspace = try create()

            lock.lock()
            defer { lock.unlock() }
            if let cached = workspaces[key] {
                return cached
            }
            workspaces[key] = preparedWorkspace
            return preparedWorkspace
        }
    }

    struct CopiedProjectAuditWorkspace {
        let workspaceRoot: URL
        let copiedProjectRoot: URL
        let copiedProjectPath: String
        let xctestRunPath: String
        let reportURL: URL
    }

    static func runAudit(
        request: IOSAccessibilityAuditRequest,
        copiedProjectCache: CopiedProjectAuditWorkspaceCache? = nil,
        commandRunner: (CommandInvocation) throws -> CommandResult,
        fileManager: FileManager
    ) throws -> IOSAccessibilityAuditExecutionResult {
        if let copiedProjectResult = try runCopiedProjectAuditIfAvailable(
            request: request,
            copiedProjectCache: copiedProjectCache,
            commandRunner: commandRunner,
            fileManager: fileManager
        ) {
            return copiedProjectResult
        }

        guard let xcodeGenPath = resolveXcodeGenPath(fileManager: fileManager) else {
            throw IOSAccessibilityAuditRunnerError.missingXcodeGen
        }

        let templateRoot = harnessTemplateRoot()
        guard fileManager.fileExists(atPath: templateRoot.path) else {
            throw IOSAccessibilityAuditRunnerError.missingHarnessTemplate(templateRoot.path)
        }

        let workspaceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("accessibility-preflight-ios-audit-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        try copyTemplate(from: templateRoot, to: workspaceRoot, fileManager: fileManager)

        let reportURL = workspaceRoot.appendingPathComponent("audit-report.json")
        try writeGeneratedConfiguration(
            to: workspaceRoot.appendingPathComponent("Sources/Generated/AuditRunConfiguration.swift"),
            bundleIdentifier: request.bundleIdentifier,
            reportPath: reportURL.path,
            fileManager: fileManager
        )

        let specPath = workspaceRoot.appendingPathComponent("project.yml").path
        let projectPath = workspaceRoot.appendingPathComponent("IOSAccessibilityAuditHarness.xcodeproj").path
        let derivedDataPath = workspaceRoot.appendingPathComponent("DerivedData").path

        let generateResult = try commandRunner(
            CommandInvocation(
                executable: xcodeGenPath,
                arguments: ["generate", "--spec", specPath, "--project", workspaceRoot.path],
                workingDirectory: workspaceRoot.path
            )
        )
        guard generateResult.exitCode == 0 else {
            throw IOSAccessibilityAuditRunnerError.generationFailed(commandFailureDetail(generateResult))
        }

        let buildForTestingResult = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcodebuild",
                arguments: [
                    "-project", projectPath,
                    "-scheme", "IOSAccessibilityAuditHarness",
                    "-destination", "platform=iOS Simulator,id=\(request.device.identifier)",
                    "-derivedDataPath", derivedDataPath,
                    "CODE_SIGNING_ALLOWED=NO",
                    "build-for-testing"
                ],
                workingDirectory: workspaceRoot.path
            )
        )
        guard buildForTestingResult.exitCode == 0 else {
            throw IOSAccessibilityAuditRunnerError.testFailed(commandFailureDetail(buildForTestingResult))
        }

        let xctestRunPath = try findXCTestRunPath(derivedDataPath: derivedDataPath, fileManager: fileManager)
        let targetAppPath = try resolveTargetAppPath(
            request: request,
            commandRunner: commandRunner
        )
        let patchedXCTestRunPath = try patchXCTestRunFile(
            atPath: xctestRunPath,
            targetAppPath: targetAppPath,
            launchEnvironment: request.launchEnvironment
        )

        let testResult = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcodebuild",
                arguments: [
                    "test-without-building",
                    "-xctestrun", patchedXCTestRunPath,
                    "-destination", "platform=iOS Simulator,id=\(request.device.identifier)"
                ],
                workingDirectory: workspaceRoot.path
            )
        )
        guard testResult.exitCode == 0 else {
            throw IOSAccessibilityAuditRunnerError.testFailed(commandFailureDetail(testResult))
        }

        return try readHarnessReport(at: reportURL, fileManager: fileManager)
    }

    static func runCopiedProjectAuditIfAvailable(
        request: IOSAccessibilityAuditRequest,
        copiedProjectCache: CopiedProjectAuditWorkspaceCache? = nil,
        commandRunner: (CommandInvocation) throws -> CommandResult,
        fileManager: FileManager
    ) throws -> IOSAccessibilityAuditExecutionResult? {
        guard let projectPath = request.projectPath else {
            return nil
        }

        let originalProjectRoot = URL(fileURLWithPath: projectPath).deletingLastPathComponent()
        let originalSpecURL = originalProjectRoot.appendingPathComponent("project.yml")
        guard fileManager.fileExists(atPath: originalSpecURL.path) else {
            return nil
        }

        guard let xcodeGenPath = resolveXcodeGenPath(fileManager: fileManager) else {
            throw IOSAccessibilityAuditRunnerError.missingXcodeGen
        }

        let workspaceKey = copiedProjectCacheKey(for: request)
        let workspace = try copiedProjectCache?.workspace(for: workspaceKey) {
            try prepareCopiedProjectAuditWorkspace(
                request: request,
                projectPath: projectPath,
                originalProjectRoot: originalProjectRoot,
                xcodeGenPath: xcodeGenPath,
                commandRunner: commandRunner,
                fileManager: fileManager
            )
        } ?? prepareCopiedProjectAuditWorkspace(
            request: request,
            projectPath: projectPath,
            originalProjectRoot: originalProjectRoot,
            xcodeGenPath: xcodeGenPath,
            commandRunner: commandRunner,
            fileManager: fileManager
        )

        if fileManager.fileExists(atPath: workspace.reportURL.path) {
            try fileManager.removeItem(at: workspace.reportURL)
        }

        let patchedXCTestRunPath = try patchXCTestRunFile(
            atPath: workspace.xctestRunPath,
            targetAppPath: nil,
            launchEnvironment: request.launchEnvironment
        )

        let testResult = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcodebuild",
                arguments: [
                    "test-without-building",
                    "-xctestrun", patchedXCTestRunPath,
                    "-destination", "platform=iOS Simulator,id=\(request.device.identifier)"
                ],
                workingDirectory: workspace.copiedProjectRoot.path
            )
        )
        guard testResult.exitCode == 0 else {
            throw IOSAccessibilityAuditRunnerError.testFailed(commandFailureDetail(testResult))
        }

        return try readHarnessReport(
            at: workspace.reportURL,
            artifactDirectory: workspace.workspaceRoot,
            artifactLabel: request.launchEnvironment["ACCESSIBILITY_PREFLIGHT_AUDIT_SCENARIO"] ?? "default",
            fileManager: fileManager
        )
    }

    static func prepareCopiedProjectAuditWorkspace(
        request: IOSAccessibilityAuditRequest,
        projectPath: String,
        originalProjectRoot: URL,
        xcodeGenPath: String,
        commandRunner: (CommandInvocation) throws -> CommandResult,
        fileManager: FileManager
    ) throws -> CopiedProjectAuditWorkspace {
        let harnessSourceRoot = harnessTemplateRoot()
        let harnessUITestSource = harnessSourceRoot
            .appendingPathComponent("Tests/AccessibilityAuditHarnessUITests/AccessibilityAuditHarnessUITests.swift")
        guard fileManager.fileExists(atPath: harnessUITestSource.path) else {
            throw IOSAccessibilityAuditRunnerError.missingHarnessTemplate(harnessUITestSource.path)
        }

        let sourceCopyRoot = originalProjectRoot.deletingLastPathComponent()
        let workspaceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("accessibility-preflight-ios-copy-\(UUID().uuidString)", isDirectory: true)
        let copiedContainerRoot = workspaceRoot.appendingPathComponent(sourceCopyRoot.lastPathComponent, isDirectory: true)
        try copyDirectory(from: sourceCopyRoot, to: copiedContainerRoot, fileManager: fileManager)

        let copiedProjectRoot = copiedContainerRoot.appendingPathComponent(originalProjectRoot.lastPathComponent, isDirectory: true)
        let copiedSpecURL = copiedProjectRoot.appendingPathComponent("project.yml")
        let copiedBaseSpecURL = copiedProjectRoot.appendingPathComponent(baseSpecFilename)
        try fileManager.moveItem(at: copiedSpecURL, to: copiedBaseSpecURL)

        let generatedSourceDirectory = copiedProjectRoot.appendingPathComponent("AccessibilityAuditGenerated", isDirectory: true)
        let harnessTestDirectory = copiedProjectRoot.appendingPathComponent("AccessibilityAuditHarnessUITests", isDirectory: true)
        try fileManager.createDirectory(at: generatedSourceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: harnessTestDirectory, withIntermediateDirectories: true)
        try copyFile(
            from: harnessUITestSource,
            to: harnessTestDirectory.appendingPathComponent("AccessibilityAuditHarnessUITests.swift"),
            fileManager: fileManager
        )

        let reportURL = workspaceRoot.appendingPathComponent("audit-report.json")
        try writeGeneratedConfiguration(
            to: generatedSourceDirectory.appendingPathComponent("AuditRunConfiguration.swift"),
            bundleIdentifier: request.bundleIdentifier,
            reportPath: reportURL.path,
            fileManager: fileManager
        )

        try writeCopiedProjectSpec(
            to: copiedSpecURL,
            baseSpecFilename: baseSpecFilename,
            overlayFilename: overlaySpecFilename,
            fileManager: fileManager
        )
        try writeCopiedProjectOverlay(
            to: copiedProjectRoot.appendingPathComponent(overlaySpecFilename),
            targetName: request.targetName,
            bundleIdentifier: request.bundleIdentifier,
            fileManager: fileManager
        )

        let generateResult = try commandRunner(
            CommandInvocation(
                executable: xcodeGenPath,
                arguments: ["generate"],
                workingDirectory: copiedProjectRoot.path
            )
        )
        guard generateResult.exitCode == 0 else {
            throw IOSAccessibilityAuditRunnerError.generationFailed(commandFailureDetail(generateResult))
        }

        let derivedDataPath = workspaceRoot.appendingPathComponent("DerivedData").path
        let copiedProjectPath = copiedProjectRoot
            .appendingPathComponent(URL(fileURLWithPath: projectPath).lastPathComponent)
            .path

        let buildForTestingResult = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcodebuild",
                arguments: [
                    "-project", copiedProjectPath,
                    "-scheme", harnessSchemeName,
                    "-destination", "platform=iOS Simulator,id=\(request.device.identifier)",
                    "-derivedDataPath", derivedDataPath,
                    "CODE_SIGNING_ALLOWED=NO",
                    "build-for-testing"
                ],
                workingDirectory: copiedProjectRoot.path
            )
        )
        guard buildForTestingResult.exitCode == 0 else {
            throw IOSAccessibilityAuditRunnerError.testFailed(commandFailureDetail(buildForTestingResult))
        }

        return CopiedProjectAuditWorkspace(
            workspaceRoot: workspaceRoot,
            copiedProjectRoot: copiedProjectRoot,
            copiedProjectPath: copiedProjectPath,
            xctestRunPath: try findXCTestRunPath(derivedDataPath: derivedDataPath, fileManager: fileManager),
            reportURL: reportURL
        )
    }

    static func resolveXcodeGenPath(fileManager: FileManager) -> String? {
        let candidates = [
            "/opt/homebrew/bin/xcodegen",
            "/usr/local/bin/xcodegen",
            "/usr/bin/xcodegen"
        ]

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    static func harnessTemplateRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Harnesses/IOSAccessibilityAuditHarness", isDirectory: true)
    }

    static func copyTemplate(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let relativePath = fileURL.path.replacingOccurrences(of: source.path + "/", with: "")
            let destinationURL = destination.appendingPathComponent(relativePath)
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                continue
            }

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: fileURL, to: destinationURL)
        }
    }

    static func writeGeneratedConfiguration(
        to destination: URL,
        bundleIdentifier: String,
        reportPath: String,
        fileManager: FileManager
    ) throws {
        let source = """
        import Foundation

        enum AuditRunConfiguration {
            static let targetBundleIdentifier = \(swiftStringLiteral(bundleIdentifier))
            static let reportPath = \(swiftStringLiteral(reportPath))
            static let activationTimeout: TimeInterval = 15
        }
        """

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: destination, atomically: true, encoding: .utf8)
    }

    static func writeCopiedProjectSpec(
        to destination: URL,
        baseSpecFilename: String,
        overlayFilename: String,
        fileManager: FileManager
    ) throws {
        let source = """
        include:
          - path: \(baseSpecFilename)
          - path: \(overlayFilename)
        """
        try source.write(to: destination, atomically: true, encoding: .utf8)
    }

    static func writeCopiedProjectOverlay(
        to destination: URL,
        targetName: String,
        bundleIdentifier: String,
        fileManager: FileManager
    ) throws {
        let source = """
        targets:
          \(harnessTargetName):
            type: bundle.ui-testing
            platform: iOS
            deploymentTarget: "17.0"
            sources:
              - path: AccessibilityAuditHarnessUITests
              - path: AccessibilityAuditGenerated
            dependencies:
              - target: \(targetName)
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: \(bundleIdentifier).accessibility-audit-tests
                PRODUCT_NAME: \(harnessTargetName)
                GENERATE_INFOPLIST_FILE: YES
                TEST_TARGET_NAME: \(targetName)
        schemes:
          \(harnessSchemeName):
            build:
              targets:
                \(targetName): all
                \(harnessTargetName): [test]
            test:
              gatherCoverageData: false
              targets:
                - name: \(harnessTargetName)
        """
        try source.write(to: destination, atomically: true, encoding: .utf8)
    }

    static func copyDirectory(from source: URL, to destination: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    static func copyFile(from source: URL, to destination: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    static func copiedProjectCacheKey(for request: IOSAccessibilityAuditRequest) -> String {
        [
            request.projectPath ?? "missing-project-path",
            request.targetName,
            request.bundleIdentifier,
            request.device.identifier
        ].joined(separator: "|")
    }

    static func readHarnessReport(
        at reportURL: URL,
        artifactDirectory: URL? = nil,
        artifactLabel: String? = nil,
        fileManager: FileManager
    ) throws -> IOSAccessibilityAuditExecutionResult {
        guard fileManager.fileExists(atPath: reportURL.path) else {
            throw IOSAccessibilityAuditRunnerError.missingReport(reportURL.path)
        }

        let stableReportURL: URL
        if let artifactDirectory {
            let copiedReportURL = artifactDirectory.appendingPathComponent(
                "audit-report-\(sanitizedArtifactLabel(artifactLabel ?? "default"))-\(UUID().uuidString).json"
            )
            if fileManager.fileExists(atPath: copiedReportURL.path) {
                try fileManager.removeItem(at: copiedReportURL)
            }
            try fileManager.copyItem(at: reportURL, to: copiedReportURL)
            stableReportURL = copiedReportURL
        } else {
            stableReportURL = reportURL
        }

        let reportData = try Data(contentsOf: stableReportURL)
        let report = try JSONDecoder().decode(HarnessReport.self, from: reportData)
        return .completed(
            IOSAccessibilityAuditCompleted(
                reportPath: stableReportURL.path,
                issues: report.issues
            )
        )
    }

    static func sanitizedArtifactLabel(_ label: String) -> String {
        let sanitized = label
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "default" : sanitized
    }

    static func swiftStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func commandFailureDetail(_ result: CommandResult) -> String {
        let detail = result.stderr.isEmpty ? result.stdout : result.stderr
        return detail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func findXCTestRunPath(
        derivedDataPath: String,
        fileManager: FileManager
    ) throws -> String {
        let productsURL = URL(fileURLWithPath: derivedDataPath, isDirectory: true)
            .appendingPathComponent("Build/Products", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: productsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw IOSAccessibilityAuditRunnerError.missingXCTestRun(productsURL.path)
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension == "xctestrun" {
                return fileURL.path
            }
        }

        throw IOSAccessibilityAuditRunnerError.missingXCTestRun(productsURL.path)
    }

    static func resolveTargetAppPath(
        request: IOSAccessibilityAuditRequest,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws -> String {
        if let appPath = request.appPath, !appPath.isEmpty {
            return appPath
        }

        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "get_app_container", request.device.identifier, request.bundleIdentifier, "app"],
                workingDirectory: nil
            )
        )
        guard result.exitCode == 0 else {
            throw IOSAccessibilityAuditRunnerError.simulatorAppPathUnavailable(commandFailureDetail(result))
        }

        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw IOSAccessibilityAuditRunnerError.simulatorAppPathUnavailable("simctl returned an empty app path.")
        }

        return path
    }

    static func patchXCTestRunFile(
        atPath path: String,
        targetAppPath: String?,
        launchEnvironment: [String: String]
    ) throws -> String {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        guard var plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw IOSAccessibilityAuditRunnerError.testFailed("Unable to read the generated .xctestrun file.")
        }

        guard let testTargetKey = plist.keys.first(where: { $0 != "__xctestrun_metadata__" }),
              var testTarget = plist[testTargetKey] as? [String: Any] else {
            throw IOSAccessibilityAuditRunnerError.testFailed("The generated .xctestrun file did not contain a UI test target.")
        }

        if let targetAppPath {
            testTarget["UITargetAppPath"] = targetAppPath
        }

        var targetAppEnvironment = testTarget["UITargetAppEnvironmentVariables"] as? [String: String] ?? [:]
        for (key, value) in launchEnvironment {
            targetAppEnvironment[key] = value
        }
        testTarget["UITargetAppEnvironmentVariables"] = targetAppEnvironment

        plist[testTargetKey] = testTarget

        let patchedURL = url.deletingPathExtension().appendingPathExtension("patched.xctestrun")
        let patchedData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try patchedData.write(to: patchedURL)
        return patchedURL.path
    }
}
