import Foundation
import AccessibilityPreflightCore

public struct DynamicTypeSweepResult: Equatable {
    public let originalContentSizeCategory: String
    public let auditedContentSizeCategory: String
    public let launch: SimulatorLaunchResult

    public init(
        originalContentSizeCategory: String,
        auditedContentSizeCategory: String,
        launch: SimulatorLaunchResult
    ) {
        self.originalContentSizeCategory = originalContentSizeCategory
        self.auditedContentSizeCategory = auditedContentSizeCategory
        self.launch = launch
    }
}

public enum DynamicTypeAuditResult: Equatable {
    case completed(DynamicTypeSweepResult)
    case skipped(reason: String)
}

public struct DynamicTypePass {
    public static let auditedContentSizeCategory = "accessibility-extra-extra-extra-large"

    private static let supportedContentSizeCategories: Set<String> = [
        "extra-small",
        "small",
        "medium",
        "large",
        "extra-large",
        "extra-extra-large",
        "extra-extra-extra-large",
        "accessibility-medium",
        "accessibility-large",
        "accessibility-extra-large",
        "accessibility-extra-extra-large",
        "accessibility-extra-extra-extra-large"
    ]

    public init() {}

    public func run(
        bundleIdentifier: String,
        on device: SimulatorDevice,
        using simulatorBootstrap: SimulatorBootstrap,
        semanticOutputPath: String? = nil
    ) -> DynamicTypeAuditResult {
        run(
            bundleIdentifier: bundleIdentifier,
            on: device,
            using: simulatorBootstrap,
            semanticOutputPath: semanticOutputPath,
            whileAuditedContentSizeIsActive: {}
        )
    }

    public func run(
        bundleIdentifier: String,
        on device: SimulatorDevice,
        using simulatorBootstrap: SimulatorBootstrap,
        semanticOutputPath: String? = nil,
        whileAuditedContentSizeIsActive auditedWork: () throws -> Void
    ) -> DynamicTypeAuditResult {
        do {
            let originalContentSizeCategory = try simulatorBootstrap.contentSizeCategory(on: device)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard Self.supportedContentSizeCategories.contains(originalContentSizeCategory) else {
                return .skipped(reason: "Simulator content size query returned '\(originalContentSizeCategory)'.")
            }

            let auditedContentSizeCategory = Self.auditedContentSizeCategory
            try simulatorBootstrap.setContentSizeCategory(auditedContentSizeCategory, on: device)
            defer {
                if originalContentSizeCategory != auditedContentSizeCategory {
                    try? simulatorBootstrap.setContentSizeCategory(originalContentSizeCategory, on: device)
                }
            }

            try? simulatorBootstrap.terminateApp(bundleIdentifier: bundleIdentifier, on: device)
            let launch = try simulatorBootstrap.launchApp(
                request: Self.semanticLaunchRequest(
                    bundleIdentifier: bundleIdentifier,
                    outputPath: semanticOutputPath ?? Self.semanticOutputPath(
                        bundleIdentifier: bundleIdentifier,
                        on: device,
                        using: simulatorBootstrap
                    )
                ),
                on: device
            )
            try auditedWork()

            return .completed(
                DynamicTypeSweepResult(
                    originalContentSizeCategory: originalContentSizeCategory,
                    auditedContentSizeCategory: auditedContentSizeCategory,
                    launch: launch
                )
            )
        } catch {
            return .skipped(reason: error.localizedDescription)
        }
    }

    public func assistedChecks(for result: DynamicTypeAuditResult) -> [String] {
        switch result {
        case .completed(let sweep):
            return [
                "Review the screens exercised at \(sweep.auditedContentSizeCategory) for clipping, truncation, and overlap."
            ]
        case .skipped:
            return [
                "Run a manual Dynamic Type review at accessibility-extra-extra-extra-large because simulator content-size automation was unavailable."
            ]
        }
    }

    private static func semanticLaunchRequest(bundleIdentifier: String, outputPath: String) -> SimulatorLaunchRequest {
        SimulatorLaunchRequest(
            bundleIdentifier: bundleIdentifier,
            environment: semanticLaunchEnvironment(outputPath: outputPath)
        )
    }

    private static func semanticLaunchEnvironment(outputPath: String) -> [String: String] {
        [
            "ACCESSIBILITY_PREFLIGHT_OUTPUT_PATH": outputPath,
            "ACCESSIBILITY_PREFLIGHT_SEMANTICS": "1"
        ]
    }

    private static func semanticOutputPath(
        bundleIdentifier: String,
        on device: SimulatorDevice,
        using simulatorBootstrap: SimulatorBootstrap
    ) -> String {
        let filename = "accessibility-preflight-\(UUID().uuidString).json"
        guard (try? simulatorBootstrap.appDataContainerPath(bundleIdentifier: bundleIdentifier, on: device)) != nil else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
                .path
        }

        return "/tmp/\(filename)"
    }
}
