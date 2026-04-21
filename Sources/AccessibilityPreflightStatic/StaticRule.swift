import Foundation
import AccessibilityPreflightReport

public protocol StaticRule {
    func scan(path: String, source: String) -> [Finding]
}
