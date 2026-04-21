import Foundation
import AccessibilityPreflightCore
import AccessibilityPreflightReport

public struct GenericAccessibilityLabelRule: StaticRule {
    public init() {}

    public func scan(path: String, source: String) -> [Finding] {
        guard source.contains(".accessibilityLabel(\"Button\")") || source.contains(".accessibilityLabel(\"Image\")") else {
            return []
        }

        return [
            Finding(
                platform: "shared",
                surface: "voiceover",
                severity: .warn,
                confidence: .heuristic,
                title: "Generic accessibility label",
                detail: "Detected an accessibility label that does not describe the control to a user.",
                fix: "Replace the generic label with a label that reflects the control's purpose.",
                evidence: ["static rule: generic label"],
                file: path,
                line: nil,
                verifiedBy: "static"
            )
        ]
    }
}
