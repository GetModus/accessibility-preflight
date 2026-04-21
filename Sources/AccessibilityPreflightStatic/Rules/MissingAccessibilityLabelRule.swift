import Foundation
import AccessibilityPreflightCore
import AccessibilityPreflightReport

public struct MissingAccessibilityLabelRule: StaticRule {
    public init() {}

    public func scan(path: String, source: String) -> [Finding] {
        guard source.contains("Button("), source.contains("Image("), !source.contains(".accessibilityLabel(") else {
            return []
        }

        return [
            Finding(
                platform: "shared",
                surface: "voiceover",
                severity: .warn,
                confidence: .heuristic,
                title: "Icon-only button lacks explicit accessibility label",
                detail: "Detected a button built from an image without a matching accessibilityLabel modifier.",
                fix: "Add a user-meaningful accessibilityLabel to the button.",
                evidence: ["static rule: icon-only button"],
                file: path,
                line: nil,
                verifiedBy: "static"
            )
        ]
    }
}
