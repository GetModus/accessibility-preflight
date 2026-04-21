import Foundation
import AccessibilityPreflightCore

public struct ResolvedBuildTarget: Equatable {
    public let projectName: String
    public let projectPath: String
    public let containerKind: XcodeContainerKind
    public let containerName: String
    public let containerPath: String
    public let schemeName: String
    public let buildableName: String?

    public init(
        projectName: String,
        projectPath: String,
        containerKind: XcodeContainerKind = .project,
        containerName: String? = nil,
        containerPath: String? = nil,
        schemeName: String,
        buildableName: String?
    ) {
        self.projectName = projectName
        self.projectPath = projectPath
        self.containerKind = containerKind
        self.containerName = containerName ?? projectName
        self.containerPath = containerPath ?? projectPath
        self.schemeName = schemeName
        self.buildableName = buildableName
    }

    public init(projectName: String, projectPath: String, schemeName: String, buildableName: String?) {
        self.init(
            projectName: projectName,
            projectPath: projectPath,
            containerKind: .project,
            containerName: projectName,
            containerPath: projectPath,
            schemeName: schemeName,
            buildableName: buildableName
        )
    }
}

public enum XcodeProjectLocatorError: LocalizedError {
    case noSharedSchemes(String)

    public var errorDescription: String? {
        switch self {
        case .noSharedSchemes(let projectName):
            return "No shared Xcode schemes were found for \(projectName)."
        }
    }
}

public enum XcodeProjectLocator {
    public static func locateProject(in root: String) throws -> String {
        try ProjectDiscovery.xcodeProjectName(in: root)
    }

    public static func locateProjectPath(in root: String) throws -> String {
        URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(try locateProject(in: root), isDirectory: true)
            .path
    }

    public static func locateContainer(in root: String) throws -> (kind: XcodeContainerKind, name: String) {
        try ProjectDiscovery.xcodeContainer(in: root)
    }

    public static func locateContainerPath(in root: String) throws -> String {
        let container = try locateContainer(in: root)
        return URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(container.name, isDirectory: true)
            .path
    }

    public static func defaultSchemeName(for projectName: String) -> String {
        URL(fileURLWithPath: projectName).deletingPathExtension().lastPathComponent
    }

    public static func resolveBuildTarget(in root: String) throws -> ResolvedBuildTarget {
        try resolveBuildTarget(in: root, preferringScheme: nil)
    }

    public static func resolveBuildTarget(
        in root: String,
        preferringScheme preferredScheme: String?,
        commandRunner: (CommandInvocation) throws -> CommandResult = ProcessCommandRunner.run
    ) throws -> ResolvedBuildTarget {
        let discovered = try ProjectDiscovery.discover(in: root)
        let projectName = discovered.projectName
        let projectPath = try locateProjectPath(in: root)
        let projectBase = defaultSchemeName(for: projectName)
        let schemeURLs = try candidateSchemeURLs(
            in: root,
            containerKind: discovered.containerKind,
            containerPath: discovered.containerPath,
            commandRunner: commandRunner
        )

        guard let schemeURL = schemeURLs.first(where: { matchesPreferredScheme($0, preferredScheme: preferredScheme) }) ??
                schemeURLs.first(where: { $0.deletingPathExtension().lastPathComponent == projectBase }) ??
                schemeURLs.first(where: { (try? String(contentsOf: $0, encoding: .utf8).contains(".app\"")) == true }) ??
                schemeURLs.first else {
            throw XcodeProjectLocatorError.noSharedSchemes(projectName)
        }

        return ResolvedBuildTarget(
            projectName: projectName,
            projectPath: projectPath,
            containerKind: discovered.containerKind,
            containerName: discovered.containerName,
            containerPath: discovered.containerPath,
            schemeName: schemeURL.deletingPathExtension().lastPathComponent,
            buildableName: preferredBuildableName(in: schemeURL)
        )
    }
}

private extension XcodeProjectLocator {
    static func sharedSchemeURLs(in projectPath: String) throws -> [URL] {
        let schemesRoot = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("xcshareddata", isDirectory: true)
            .appendingPathComponent("xcschemes", isDirectory: true)

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: schemesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension == "xcscheme" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func recursiveSchemeURLs(in root: String) throws -> [URL] {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let urls = try enumerator?.compactMap { element -> URL? in
            guard let url = element as? URL, url.pathExtension == "xcscheme" else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        } ?? []

        return urls.sorted { $0.path < $1.path }
    }

    static func candidateSchemeURLs(
        in root: String,
        containerKind: XcodeContainerKind,
        containerPath: String,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws -> [URL] {
        switch containerKind {
        case .project:
            let shared = try sharedSchemeURLs(in: containerPath)
            if !shared.isEmpty {
                return shared
            }
            let schemeNames = try projectSchemeNames(containerPath: containerPath, commandRunner: commandRunner)
            if !schemeNames.isEmpty {
                return schemeNames.map {
                    URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("\($0).xcscheme")
                }
            }
            return try recursiveSchemeURLs(in: root)
        case .workspace:
            let schemeNames = try workspaceSchemeNames(containerPath: containerPath, commandRunner: commandRunner)
            let recursive = try recursiveSchemeURLs(in: root)
            let matching = recursive.filter { schemeNames.contains($0.deletingPathExtension().lastPathComponent) }
            if !matching.isEmpty {
                return matching
            }
            if !schemeNames.isEmpty {
                return schemeNames.map {
                    URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("\($0).xcscheme")
                }
            }
            return recursive
        }
    }

    static func workspaceSchemeNames(
        containerPath: String,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws -> [String] {
        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcodebuild",
                arguments: ["-workspace", containerPath, "-list", "-json"],
                workingDirectory: URL(fileURLWithPath: containerPath).deletingLastPathComponent().path
            )
        )

        guard result.exitCode == 0 else {
            return []
        }

        let listing = try JSONDecoder().decode(XcodeListOutput.self, from: Data(result.stdout.utf8))
        return listing.workspace?.schemes ?? []
    }

    static func projectSchemeNames(
        containerPath: String,
        commandRunner: (CommandInvocation) throws -> CommandResult
    ) throws -> [String] {
        let result = try commandRunner(
            CommandInvocation(
                executable: "/usr/bin/xcodebuild",
                arguments: ["-project", containerPath, "-list", "-json"],
                workingDirectory: URL(fileURLWithPath: containerPath).deletingLastPathComponent().path
            )
        )

        guard result.exitCode == 0 else {
            return []
        }

        let listing = try JSONDecoder().decode(XcodeListOutput.self, from: Data(result.stdout.utf8))
        return listing.project?.schemes ?? []
    }

    static func preferredBuildableName(in schemeURL: URL) -> String? {
        guard let contents = try? String(contentsOf: schemeURL, encoding: .utf8) else {
            return nil
        }

        let appMatches = matches(in: contents, pattern: #"BuildableName = "([^"]+\.app)""#)
        if let app = appMatches.first {
            return app
        }

        return matches(in: contents, pattern: #"BuildableName = "([^"]+)""#).first
    }

    static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[capture])
        }
    }

    static func matchesPreferredScheme(_ schemeURL: URL, preferredScheme: String?) -> Bool {
        guard let preferredScheme, !preferredScheme.isEmpty else {
            return false
        }

        let normalizedPreferred = normalizedTargetName(preferredScheme)
        let schemeName = normalizedTargetName(schemeURL.deletingPathExtension().lastPathComponent)
        if schemeName == normalizedPreferred {
            return true
        }

        guard let buildableName = preferredBuildableName(in: schemeURL) else {
            return false
        }

        return normalizedTargetName(buildableName) == normalizedPreferred
    }

    static func normalizedTargetName(_ name: String) -> String {
        URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
    }
}

private struct XcodeListOutput: Decodable {
    let workspace: XcodeSchemeList?
    let project: XcodeSchemeList?
}

private struct XcodeSchemeList: Decodable {
    let schemes: [String]?
}
