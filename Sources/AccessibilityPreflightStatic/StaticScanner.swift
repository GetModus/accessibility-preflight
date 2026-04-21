import Foundation
import AccessibilityPreflightReport

public struct StaticScanner {
    public let rules: [any StaticRule]

    public init(rules: [any StaticRule] = StaticScanner.defaultRules) {
        self.rules = rules
    }

    public func scan(path: String, source: String) -> [Finding] {
        rules.flatMap { $0.scan(path: path, source: source) }
    }

    public static var defaultRules: [any StaticRule] {
        [
            MissingAccessibilityLabelRule(),
            GenericAccessibilityLabelRule(),
            FixedTypeSizeRule(),
            FixedCustomFontRule()
        ]
    }
}
