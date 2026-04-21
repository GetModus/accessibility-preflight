import Foundation

public enum SemanticIntegrationStatus: Equatable {
    case installed
    case missing
}

public struct SemanticIntegrationAdvice: Equatable {
    public let status: SemanticIntegrationStatus
    public let warningText: String
    public let artifactPath: String?

    public init(status: SemanticIntegrationStatus, warningText: String, artifactPath: String?) {
        self.status = status
        self.warningText = warningText
        self.artifactPath = artifactPath
    }
}

public struct SemanticIntegrationAdvisor {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func advise(projectRoot: String, appRoot: String, appSlug: String) throws -> SemanticIntegrationAdvice {
        if SemanticIntegrationArtifact.hasInstalledSemanticExport(in: appRoot, fileManager: fileManager) {
            return SemanticIntegrationAdvice(
                status: .installed,
                warningText: "Semantic integration is already installed for \(appSlug). no app code was changed automatically.",
                artifactPath: nil
            )
        }

        let artifact = SemanticIntegrationArtifact(
            projectRoot: projectRoot,
            appRoot: appRoot,
            appSlug: appSlug,
            fileManager: fileManager
        )
        let artifactPath = try artifact.generate()

        return SemanticIntegrationAdvice(
            status: .missing,
            warningText: "Semantic integration is missing for \(appSlug). no app code was changed automatically; a standalone review artifact was generated instead.",
            artifactPath: artifactPath
        )
    }
}
