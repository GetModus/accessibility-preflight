import Foundation

public enum XcodeContainerKind: String, Codable, Equatable {
    case project
    case workspace
}

public struct DiscoveredProject: Equatable {
    public let rootPath: String
    public let platform: String
    public let projectName: String
    public let containerKind: XcodeContainerKind
    public let containerName: String
    public let containerPath: String

    public init(
        rootPath: String,
        platform: String,
        projectName: String,
        containerKind: XcodeContainerKind = .project,
        containerName: String? = nil,
        containerPath: String? = nil
    ) {
        self.rootPath = rootPath
        self.platform = platform
        self.projectName = projectName
        self.containerKind = containerKind
        self.containerName = containerName ?? projectName
        self.containerPath = containerPath ?? URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(projectName, isDirectory: true)
            .path
    }
}

public enum ProjectDiscoveryError: LocalizedError {
    case noXcodeProject(String)

    public var errorDescription: String? {
        switch self {
        case .noXcodeProject(let root):
            return "No Xcode project was found in \(root)."
        }
    }
}

public enum ProjectDiscovery {
    public static func discover(in root: String) throws -> DiscoveredProject {
        let projectName = try xcodeProjectName(in: root)
        let container = try xcodeContainer(in: root)
        let platform = inferredPlatform(for: root)

        return DiscoveredProject(
            rootPath: root,
            platform: platform,
            projectName: projectName,
            containerKind: container.kind,
            containerName: container.name,
            containerPath: URL(fileURLWithPath: root, isDirectory: true)
                .appendingPathComponent(container.name, isDirectory: true)
                .path
        )
    }

    public static func xcodeProjectName(in root: String) throws -> String {
        let projectNames = try FileManager.default.contentsOfDirectory(atPath: root)
            .filter { $0.hasSuffix(".xcodeproj") }
            .sorted()

        if let matching = projectNames.first(where: {
            $0 == "\(URL(fileURLWithPath: root, isDirectory: true).lastPathComponent).xcodeproj"
        }) {
            return matching
        }

        guard let first = projectNames.first else {
            throw ProjectDiscoveryError.noXcodeProject(root)
        }

        return first
    }

    public static func xcodeContainer(in root: String) throws -> (kind: XcodeContainerKind, name: String) {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let childNames = try FileManager.default.contentsOfDirectory(atPath: root)
        let workspaceNames = childNames
            .filter { $0.hasSuffix(".xcworkspace") }
            .sorted()
        let projectNames = childNames
            .filter { $0.hasSuffix(".xcodeproj") }
            .sorted()
        let preferredBaseName = rootURL.lastPathComponent

        if let matchingWorkspace = workspaceNames.first(where: {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent == preferredBaseName
        }) ?? workspaceNames.first {
            return (.workspace, matchingWorkspace)
        }

        if let matchingProject = projectNames.first(where: {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent == preferredBaseName
        }) ?? projectNames.first {
            return (.project, matchingProject)
        }

        throw ProjectDiscoveryError.noXcodeProject(root)
    }

    private static func inferredPlatform(for root: String) -> String {
        let components = URL(fileURLWithPath: root).pathComponents.map { $0.lowercased() }
        if components.contains("macos") || components.contains("mac") {
            return "macos"
        }

        if xcodeProjectTargetsMacOS(in: root) {
            return "macos"
        }

        return "ios"
    }

    private static func xcodeProjectTargetsMacOS(in root: String) -> Bool {
        guard let projectName = try? xcodeProjectName(in: root), projectName != "Unknown.xcodeproj" else {
            return false
        }

        let pbxprojPath = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(projectName, isDirectory: true)
            .appendingPathComponent("project.pbxproj")
            .path

        guard let contents = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else {
            return false
        }

        return contents.contains("SDKROOT = macosx") || contents.contains("SUPPORTED_PLATFORMS = macosx")
    }
}
