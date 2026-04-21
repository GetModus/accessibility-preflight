import Foundation

public struct BuildResult: Equatable {
    public let buildPath: String
    public let executablePath: String?
    public let bundleIdentifier: String?
    public let scheme: String

    public init(buildPath: String, executablePath: String?, bundleIdentifier: String?, scheme: String) {
        self.buildPath = buildPath
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.scheme = scheme
    }
}

public struct CommandInvocation: Equatable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let environment: [String: String]

    public init(executable: String, arguments: [String], workingDirectory: String?, environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

public struct CommandResult: Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public enum ProcessCommandRunner {
    public static func run(_ invocation: CommandInvocation) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        if let workingDirectory = invocation.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }
        if !invocation.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(invocation.environment) { _, new in new }
        }

        let stdoutURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stderrURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()

        let stdout = String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self)
        let stderr = String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
        return CommandResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}

public enum XcodeBuilderError: LocalizedError {
    case buildSettingsFailed(String)
    case buildFailed(String)
    case missingBuildSettings
    case missingProjectArtifact(String)

    public var errorDescription: String? {
        switch self {
        case .buildSettingsFailed(let detail):
            return "Failed to load Xcode build settings: \(detail)"
        case .buildFailed(let detail):
            return "Xcode build failed: \(detail)"
        case .missingBuildSettings:
            return "No build settings were returned for the requested scheme."
        case .missingProjectArtifact(let path):
            return "Expected build artifact was not found at \(path)."
        }
    }
}

public enum XcodeBuilder {
    public static func defaultBuild(target: ResolvedBuildTarget, destination: String) throws -> BuildResult {
        try build(target: target, destination: destination)
    }

    public static func build(
        projectRoot: String,
        scheme: String,
        destination: String,
        derivedDataPath: String? = nil,
        commandRunner: (CommandInvocation) throws -> CommandResult = ProcessCommandRunner.run,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> BuildResult {
        try build(
            target: try XcodeProjectLocator.resolveBuildTarget(
                in: projectRoot,
                preferringScheme: scheme,
                commandRunner: commandRunner
            ),
            destination: destination,
            derivedDataPath: derivedDataPath,
            commandRunner: commandRunner,
            fileExists: fileExists
        )
    }

    public static func build(
        target: ResolvedBuildTarget,
        destination: String,
        derivedDataPath: String? = nil,
        commandRunner: (CommandInvocation) throws -> CommandResult = ProcessCommandRunner.run,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> BuildResult {
        let derivedDataPath = derivedDataPath ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .path

        let containerArguments = [
            target.containerKind == .workspace ? "-workspace" : "-project",
            target.containerKind == .workspace ? target.containerPath : target.projectPath
        ]

        let commonArguments = containerArguments + [
            "-scheme", target.schemeName,
            "-destination", destination,
            "-derivedDataPath", derivedDataPath
        ]

        let settingsResult = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcodebuild",
                arguments: commonArguments + ["-showBuildSettings", "-json"],
                workingDirectory: URL(fileURLWithPath: target.projectPath).deletingLastPathComponent().path
            )
        )

        guard settingsResult.exitCode == 0 else {
            throw XcodeBuilderError.buildSettingsFailed(settingsResult.stderr.isEmpty ? settingsResult.stdout : settingsResult.stderr)
        }

        let buildResult = try selectBuildResult(
            from: settingsResult.stdout,
            scheme: target.schemeName,
            preferredProductName: target.buildableName
        )
        let buildInvocation = CommandInvocation(
            executable: "/usr/bin/xcodebuild",
            arguments: commonArguments + ["build"],
            workingDirectory: URL(fileURLWithPath: target.projectPath).deletingLastPathComponent().path
        )
        let buildCommandResult = try commandRunner(buildInvocation)

        guard buildCommandResult.exitCode == 0 else {
            throw XcodeBuilderError.buildFailed(buildCommandResult.stderr.isEmpty ? buildCommandResult.stdout : buildCommandResult.stderr)
        }

        guard fileExists(buildResult.buildPath) else {
            throw XcodeBuilderError.missingProjectArtifact(buildResult.buildPath)
        }

        return buildResult
    }

    private static func selectBuildResult(
        from settingsJSON: String,
        scheme: String,
        preferredProductName: String?
    ) throws -> BuildResult {
        let decoder = JSONDecoder()
        let entries = try decoder.decode([BuildSettingsEntry].self, from: Data(settingsJSON.utf8))
        let allSettings = entries.map(\.buildSettings)
        guard let settings =
            allSettings.first(where: { $0.wrapperName == preferredProductName }) ??
            allSettings.first(where: { ($0.wrapperName ?? "").hasSuffix(".app") }) ??
            entries.first?.buildSettings else {
            throw XcodeBuilderError.missingBuildSettings
        }

        guard let targetBuildDir = settings.targetBuildDir, let wrapperName = settings.wrapperName else {
            throw XcodeBuilderError.missingBuildSettings
        }

        let buildPath = URL(fileURLWithPath: targetBuildDir, isDirectory: true)
            .appendingPathComponent(wrapperName, isDirectory: wrapperName.hasSuffix(".app"))
            .path

        let executablePath = settings.executablePath.map {
            URL(fileURLWithPath: targetBuildDir, isDirectory: true).appendingPathComponent($0).path
        }

        return BuildResult(
            buildPath: buildPath,
            executablePath: executablePath,
            bundleIdentifier: settings.bundleIdentifier,
            scheme: scheme
        )
    }
}

private struct BuildSettingsEntry: Decodable {
    let buildSettings: BuildSettings
}

private struct BuildSettings: Decodable {
    let targetBuildDir: String?
    let wrapperName: String?
    let bundleIdentifier: String?
    let executablePath: String?

    private enum CodingKeys: String, CodingKey {
        case targetBuildDir = "TARGET_BUILD_DIR"
        case wrapperName = "WRAPPER_NAME"
        case bundleIdentifier = "PRODUCT_BUNDLE_IDENTIFIER"
        case executablePath = "EXECUTABLE_PATH"
    }
}
