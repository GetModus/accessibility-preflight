import Foundation
import CoreGraphics
import AppKit
import Vision
import AccessibilityPreflightBuild

public struct VisibleTextObservation: Equatable {
    public let text: String
    public let frame: CGRect

    public init(text: String, frame: CGRect) {
        self.text = text
        self.frame = frame
    }
}

public struct SimulatorScreenInspectionResult: Equatable {
    public let screenshotPath: String
    public let recognizedTexts: [String]
    public let readingOrder: [String]
    public let duplicateCommandNames: [String]
    public let truncationCandidates: [String]
    public let crowdedTextPairs: [String]

    public init(
        screenshotPath: String,
        recognizedTexts: [String],
        readingOrder: [String],
        duplicateCommandNames: [String],
        truncationCandidates: [String],
        crowdedTextPairs: [String]
    ) {
        self.screenshotPath = screenshotPath
        self.recognizedTexts = recognizedTexts
        self.readingOrder = readingOrder
        self.duplicateCommandNames = duplicateCommandNames
        self.truncationCandidates = truncationCandidates
        self.crowdedTextPairs = crowdedTextPairs
    }
}

public enum SimulatorScreenInspectorError: LocalizedError {
    case screenshotFailed(String)
    case imageLoadFailed(String)
    case textRecognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .screenshotFailed(let detail):
            return "Failed to capture simulator screenshot: \(detail)"
        case .imageLoadFailed(let path):
            return "Failed to load screenshot image at \(path)"
        case .textRecognitionFailed(let detail):
            return "Failed to recognize text in simulator screenshot: \(detail)"
        }
    }
}

public struct SimulatorScreenInspector {
    private let inspectHandler: (SimulatorDevice, String) throws -> SimulatorScreenInspectionResult

    public init(
        commandRunner: @escaping (CommandInvocation) throws -> CommandResult = ProcessCommandRunner.run
    ) {
        self.inspectHandler = { device, label in
            let screenshotPath = try Self.captureScreenshot(on: device, label: label, commandRunner: commandRunner)
            let observations = try Self.recognizeText(in: screenshotPath)
            return Self.analyze(observations: observations, screenshotPath: screenshotPath)
        }
    }

    public init(
        inspect: @escaping (SimulatorDevice, String) throws -> SimulatorScreenInspectionResult
    ) {
        self.inspectHandler = inspect
    }

    public func inspect(on device: SimulatorDevice, label: String) throws -> SimulatorScreenInspectionResult {
        try inspectHandler(device, label)
    }

    public static func analyze(
        observations: [VisibleTextObservation],
        screenshotPath: String
    ) -> SimulatorScreenInspectionResult {
        let normalized = observations.compactMap { observation -> VisibleTextObservation? in
            let text = normalize(observation.text)
            guard !text.isEmpty else {
                return nil
            }
            return VisibleTextObservation(text: text, frame: observation.frame)
        }
        let filtered = filterNoise(in: normalized)

        let readingOrder = filtered
            .sorted { lhs, rhs in
                if abs(lhs.frame.minY - rhs.frame.minY) > 6 {
                    return lhs.frame.minY < rhs.frame.minY
                }
                return lhs.frame.minX < rhs.frame.minX
            }
            .map(\.text)

        let duplicateCommandNames = Dictionary(grouping: filtered) { normalizeKey($0.text) }
            .values
            .compactMap { group -> String? in
                guard group.count > 1, let first = group.first, first.text.count > 1 else {
                    return nil
                }
                return first.text
            }
            .sorted()

        let truncationCandidates = filtered
            .map(\.text)
            .filter { $0.contains("…") || $0.contains("...") }

        var crowdedTextPairs: [String] = []
        for (index, observation) in filtered.enumerated() {
            guard index + 1 < filtered.count else {
                continue
            }

            for candidate in filtered[(index + 1)..<filtered.count] {
                let intersection = observation.frame.intersection(candidate.frame)
                guard !intersection.isNull else {
                    continue
                }

                let minArea = min(observation.frame.width * observation.frame.height, candidate.frame.width * candidate.frame.height)
                guard minArea > 0 else {
                    continue
                }

                let overlapRatio = (intersection.width * intersection.height) / minArea
                if overlapRatio >= 0.25 {
                    crowdedTextPairs.append("\(observation.text) <> \(candidate.text)")
                }
            }
        }

        return SimulatorScreenInspectionResult(
            screenshotPath: screenshotPath,
            recognizedTexts: filtered.map(\.text),
            readingOrder: readingOrder,
            duplicateCommandNames: duplicateCommandNames,
            truncationCandidates: truncationCandidates,
            crowdedTextPairs: crowdedTextPairs.sorted()
        )
    }
}

private extension SimulatorScreenInspector {
    static func captureScreenshot(
        on device: SimulatorDevice,
        label: String,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws -> String {
        let sanitizedLabel = normalizeKey(label).replacingOccurrences(of: " ", with: "-")
        let screenshotPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("accessibility-preflight-\(device.identifier)-\(sanitizedLabel)-\(UUID().uuidString).png")
            .path

        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "io", device.identifier, "screenshot", screenshotPath],
                workingDirectory: nil
            )
        )
        guard result.exitCode == 0 else {
            throw SimulatorScreenInspectorError.screenshotFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        return screenshotPath
    }

    static func recognizeText(in screenshotPath: String) throws -> [VisibleTextObservation] {
        guard let image = NSImage(contentsOfFile: screenshotPath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SimulatorScreenInspectorError.imageLoadFailed(screenshotPath)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            throw SimulatorScreenInspectorError.textRecognitionFailed(error.localizedDescription)
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        return (request.results ?? []).compactMap { observation -> VisibleTextObservation? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let boundingBox = observation.boundingBox
            let frame = CGRect(
                x: boundingBox.minX * width,
                y: (1 - boundingBox.maxY) * height,
                width: boundingBox.width * width,
                height: boundingBox.height * height
            )

            return VisibleTextObservation(text: candidate.string, frame: frame)
        }
    }

    static func normalize(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeKey(_ text: String) -> String {
        normalize(text).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func filterNoise(in observations: [VisibleTextObservation]) -> [VisibleTextObservation] {
        let withoutLowSignalFragments = observations.filter { !isLowSignalFragment($0.text) }
        let withoutStatusBar = withoutLowSignalFragments.filter { !isStatusBarNoise($0.text) }

        guard let permissionDialogRect = permissionDialogBounds(in: withoutStatusBar) else {
            return withoutStatusBar
        }

        return withoutStatusBar.filter { observation in
            observation.frame.intersection(permissionDialogRect).isNull
        }
    }

    static func isStatusBarNoise(_ text: String) -> Bool {
        let normalizedText = normalizeKey(text)
        if normalizedText.range(
            of: #"^\d{1,2}:\d{2}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        return false
    }

    static func isLowSignalFragment(_ text: String) -> Bool {
        let normalizedText = normalize(text)

        if normalizedText.range(
            of: #"^[A-Za-z]$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if normalizedText.range(
            of: #"^[:.\-]?\d{2}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        return false
    }

    static func permissionDialogBounds(in observations: [VisibleTextObservation]) -> CGRect? {
        let normalizedTexts = observations.map { normalizeKey($0.text) }
        let hasPermissionTitle = normalizedTexts.contains { $0.contains("would like to") }
        let hasPermissionBody = normalizedTexts.contains {
            $0.contains("notifications may include") ||
            $0.contains("allow once") ||
            $0.contains("while using the app") ||
            $0.contains("paste from") ||
            $0.contains("would like to access")
        }
        let hasPermissionActions = normalizedTexts.contains("allow") ||
            normalizedTexts.contains("don't allow") ||
            normalizedTexts.contains("dont allow") ||
            normalizedTexts.contains("ok")

        guard hasPermissionTitle, (hasPermissionBody || hasPermissionActions) else {
            return nil
        }

        let dialogObservations = observations.filter { observation in
            let text = normalizeKey(observation.text)
            return text.contains("would like to") ||
                text.contains("notifications may include") ||
                text.contains("allow once") ||
                text.contains("while using the app") ||
                text.contains("paste from") ||
                text.contains("would like to access") ||
                text == "allow" ||
                text == "don't allow" ||
                text == "dont allow" ||
                text == "ok"
        }

        guard let first = dialogObservations.first else {
            return nil
        }

        let unionRect = dialogObservations.dropFirst().reduce(first.frame) { partial, observation in
            partial.union(observation.frame)
        }

        return unionRect.insetBy(dx: -24, dy: -24)
    }
}
