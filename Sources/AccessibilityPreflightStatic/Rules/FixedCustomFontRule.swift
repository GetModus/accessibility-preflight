import Foundation
import AccessibilityPreflightCore
import AccessibilityPreflightReport

public struct FixedCustomFontRule: StaticRule {
    public init() {}

    public func scan(path: String, source: String) -> [Finding] {
        guard source.contains(".font(.custom(") else {
            return []
        }

        let pattern = #"\.font\(\.custom\(([^)]*)\)\)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let searchRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let hasFixedCustomFont = regex?.matches(in: source, range: searchRange).contains { match in
            guard let range = Range(match.range(at: 1), in: source) else {
                return false
            }

            let arguments = String(source[range])
            return arguments.contains("size:") && !arguments.contains("relativeTo:")
        } ?? false

        guard hasFixedCustomFont else {
            return []
        }

        return [
            Finding(
                platform: "shared",
                surface: "dynamic-type",
                severity: .warn,
                confidence: .heuristic,
                title: "Fixed custom font point size",
                detail: "Detected a custom font using a fixed point size without a relative text style for Dynamic Type.",
                fix: "Add a relativeTo text style such as .body so the custom font scales with Dynamic Type.",
                evidence: ["static rule: fixed custom font size without relative text style"],
                file: path,
                line: nil,
                verifiedBy: "static"
            )
        ]
    }
}
