import Foundation
import AccessibilityPreflightCore
import AccessibilityPreflightReport

public struct FixedTypeSizeRule: StaticRule {
    public init() {}

    public func scan(path: String, source: String) -> [Finding] {
        guard source.contains(".font(.system(size:") else {
            return []
        }

        return [
            Finding(
                platform: "shared",
                surface: "dynamic-type",
                severity: .warn,
                confidence: .heuristic,
                title: "Fixed font point size",
                detail: "Detected text styled with a fixed system font size instead of dynamic type-aware styles.",
                fix: "Use a text style such as .body or .headline and let Dynamic Type scale it.",
                evidence: ["static rule: fixed point font size"],
                file: path,
                line: nil,
                verifiedBy: "static"
            )
        ]
    }
}
