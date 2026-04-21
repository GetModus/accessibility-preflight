import Foundation
import AccessibilityPreflightCore

public struct SemanticSnapshotReader {
    public init() {}

    public func read(from path: String) throws -> AppSemanticSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(AppSemanticSnapshot.self, from: data)
    }
}
