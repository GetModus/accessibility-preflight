import Foundation
import AccessibilityPreflightReport

public struct MissingDialogEscapeRule: StaticRule {
    public init() {}

    public func scan(path: String, source: String) -> [Finding] {
        []
    }
}
