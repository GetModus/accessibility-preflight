import Foundation
import AccessibilityPreflightBuild
import AccessibilityPreflightReport

public struct MacLaunchResult: Equatable {
    public let processIdentifiers: [String]
    public let launchDetail: String

    public init(processIdentifiers: [String], launchDetail: String) {
        self.processIdentifiers = processIdentifiers
        self.launchDetail = launchDetail
    }
}

public enum MacRuntimeVerifierError: LocalizedError {
    case executableMissing(String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableMissing(let scheme):
            return "Built macOS app for scheme \(scheme) did not expose a launchable executable path."
        case .launchFailed(let detail):
            return "Failed to launch the macOS app: \(detail)"
        }
    }
}

public struct MacRuntimeVerifier {
    private let targetResolver: (String, String?) throws -> ResolvedBuildTarget
    private let builder: (ResolvedBuildTarget, String) throws -> BuildResult
    private let launcher: (BuildResult) throws -> MacLaunchResult

    public init(
        targetResolver: @escaping (String, String?) throws -> ResolvedBuildTarget = { projectRoot, preferredScheme in
            try XcodeProjectLocator.resolveBuildTarget(in: projectRoot, preferringScheme: preferredScheme)
        },
        builder: @escaping (ResolvedBuildTarget, String) throws -> BuildResult = XcodeBuilder.defaultBuild,
        launcher: @escaping (BuildResult) throws -> MacLaunchResult = MacRuntimeVerifier.defaultLauncher
    ) {
        self.targetResolver = targetResolver
        self.builder = builder
        self.launcher = launcher
    }

    public func verify(projectRoot: String, appName: String) async throws -> RuntimeVerificationResult {
        let target = try targetResolver(projectRoot, appName)
        let build = try builder(target, "platform=macOS")
        guard build.executablePath != nil else {
            throw MacRuntimeVerifierError.executableMissing(build.scheme)
        }

        let launch = try launcher(build)
        let evidence = [
            "bundle_id=\(build.bundleIdentifier ?? "unknown")",
            "app_path=\(build.buildPath)",
            "scheme=\(build.scheme)",
            "launch_detail=\(launch.launchDetail)",
            "pids=\(launch.processIdentifiers.joined(separator: ","))"
        ]

        return RuntimeVerificationResult(
            findings: [
                Finding(
                    platform: "macos",
                    surface: "runtime",
                    severity: .info,
                    confidence: .proven,
                    title: "macOS app launch succeeded",
                    detail: "Built \(build.scheme) for macOS and launched the resulting app bundle.",
                    fix: "Continue with assisted VoiceOver, keyboard navigation, and focus-order checks on the launched app.",
                    evidence: evidence,
                    file: nil,
                    line: nil,
                    verifiedBy: "runtime"
                )
            ],
            assistedChecks: [
                "Verify VoiceOver rotor order in the primary window.",
                "Verify keyboard-only traversal through the primary window, toolbar, and dialogs."
            ]
        )
    }
}

extension MacRuntimeVerifier {
    public static func defaultLauncher(buildResult: BuildResult) throws -> MacLaunchResult {
        guard let executablePath = buildResult.executablePath else {
            throw MacRuntimeVerifierError.executableMissing(buildResult.scheme)
        }

        let before = try processIdentifiers(for: executablePath)
        let openResult = try ProcessCommandRunner.run(
            CommandInvocation(
                executable: "/usr/bin/open",
                arguments: ["-n", buildResult.buildPath],
                workingDirectory: nil
            )
        )
        guard openResult.exitCode == 0 else {
            throw MacRuntimeVerifierError.launchFailed(openResult.stderr.isEmpty ? openResult.stdout : openResult.stderr)
        }

        let deadline = Date().addingTimeInterval(5)
        var launched: [String] = []
        while Date() < deadline {
            let after = try processIdentifiers(for: executablePath)
            launched = after.filter { !before.contains($0) }
            if !launched.isEmpty {
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        guard !launched.isEmpty else {
            throw MacRuntimeVerifierError.launchFailed("Launch request succeeded but no new process appeared for \(executablePath).")
        }

        return MacLaunchResult(processIdentifiers: launched, launchDetail: "open request accepted")
    }

    static func processIdentifiers(for executablePath: String) throws -> [String] {
        let result = try ProcessCommandRunner.run(
            CommandInvocation(
                executable: "/usr/bin/pgrep",
                arguments: ["-f", executablePath],
                workingDirectory: nil
            )
        )

        guard result.exitCode == 0 else {
            return []
        }

        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
