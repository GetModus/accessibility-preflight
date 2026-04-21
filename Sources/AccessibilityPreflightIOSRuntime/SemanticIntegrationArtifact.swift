import Foundation

public struct SemanticIntegrationArtifact {
    public let projectRoot: String
    public let appRoot: String
    public let appSlug: String
    public let fileManager: FileManager

    public init(projectRoot: String, appRoot: String, appSlug: String, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot
        self.appRoot = appRoot
        self.appSlug = appSlug
        self.fileManager = fileManager
    }

    public func generate() throws -> String {
        let artifactDirectory = artifactDirectoryURL()
        try fileManager.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

        let readmeURL = artifactDirectory.appendingPathComponent("README.md")
        let exportURL = artifactDirectory.appendingPathComponent("AccessibilityPreflightSemanticExport.swift")

        try renderTemplate(at: readmeTemplateURL(), substitutions: substitutions())
            .write(to: readmeURL, atomically: true, encoding: .utf8)
        try renderTemplate(at: exportTemplateURL(), substitutions: substitutions())
            .write(to: exportURL, atomically: true, encoding: .utf8)

        return artifactDirectory.path
    }

    public static func hasInstalledSemanticExport(in appRoot: String, fileManager: FileManager = .default) -> Bool {
        let rootURL = URL(fileURLWithPath: appRoot, isDirectory: true)
        return installedSemanticExportCandidates(in: rootURL, fileManager: fileManager).contains {
            isInstalledSemanticExport(at: $0, fileManager: fileManager)
        }
    }

    private static func isInstalledSemanticExport(at url: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }

        let sanitizedContents = removeCommentsAndStrings(from: contents)
        let declarationPatterns = [
            #"(?:public|internal|private|fileprivate|package)?\s*(?:final\s+)?(?:class|struct|enum)\s+AccessibilityPreflightSemanticExport\b"#,
            #"(?:public|internal|private|fileprivate|package)?\s*extension\s+AccessibilityPreflightSemanticExport\b"#
        ]

        return declarationPatterns.contains {
            sanitizedContents.range(of: $0, options: .regularExpression) != nil
        }
    }

    private static func removeCommentsAndStrings(from contents: String) -> String {
        var result = String()
        result.reserveCapacity(contents.count)

        var index = contents.startIndex
        var blockCommentDepth = 0
        var inLineComment = false
        var inString = false
        var inMultilineString = false

        func appendReplacement(for character: Character) {
            if character == "\n" || character == "\r" {
                result.append(character)
            } else {
                result.append(" ")
            }
        }

        while index < contents.endIndex {
            if inLineComment {
                let character = contents[index]
                if character == "\n" {
                    inLineComment = false
                    result.append(character)
                } else {
                    result.append(" ")
                }
                index = contents.index(after: index)
                continue
            }

            if blockCommentDepth > 0 {
                if contents[index...].hasPrefix("/*") {
                    blockCommentDepth += 1
                    result.append("  ")
                    index = contents.index(index, offsetBy: 2)
                    continue
                }

                if contents[index...].hasPrefix("*/") {
                    blockCommentDepth -= 1
                    result.append("  ")
                    index = contents.index(index, offsetBy: 2)
                    continue
                }

                appendReplacement(for: contents[index])
                index = contents.index(after: index)
                continue
            }

            if inMultilineString {
                if contents[index...].hasPrefix("\"\"\"") {
                    inMultilineString = false
                    result.append("   ")
                    index = contents.index(index, offsetBy: 3)
                    continue
                }

                appendReplacement(for: contents[index])
                index = contents.index(after: index)
                continue
            }

            if inString {
                let character = contents[index]
                if character == "\\" {
                    result.append(" ")
                    let nextIndex = contents.index(after: index)
                    if nextIndex < contents.endIndex {
                        appendReplacement(for: contents[nextIndex])
                        index = contents.index(after: nextIndex)
                    } else {
                        index = nextIndex
                    }
                    continue
                }

                if character == "\"" {
                    inString = false
                    result.append(character)
                } else {
                    appendReplacement(for: character)
                }
                index = contents.index(after: index)
                continue
            }

            if contents[index...].hasPrefix("//") {
                inLineComment = true
                result.append("  ")
                index = contents.index(index, offsetBy: 2)
                continue
            }

            if contents[index...].hasPrefix("/*") {
                blockCommentDepth = 1
                result.append("  ")
                index = contents.index(index, offsetBy: 2)
                continue
            }

            if contents[index...].hasPrefix("\"\"\"") {
                inMultilineString = true
                result.append("   ")
                index = contents.index(index, offsetBy: 3)
                continue
            }

            let character = contents[index]
            if character == "\"" {
                inString = true
            }
            result.append(character)
            index = contents.index(after: index)
        }

        return result
    }
}

private extension SemanticIntegrationArtifact {
    static func installedSemanticExportCandidates(in rootURL: URL, fileManager: FileManager) -> [URL] {
        let filename = "AccessibilityPreflightSemanticExport.swift"
        var candidates = [
            rootURL.appendingPathComponent(filename),
            rootURL.appendingPathComponent("Sources", isDirectory: true).appendingPathComponent(filename)
        ]

        guard let childNames = try? fileManager.contentsOfDirectory(atPath: rootURL.path) else {
            return candidates
        }

        for childName in childNames {
            let childURL = rootURL.appendingPathComponent(childName, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            candidates.append(childURL.appendingPathComponent(filename))
            candidates.append(childURL.appendingPathComponent("Sources", isDirectory: true).appendingPathComponent(filename))
        }

        return candidates
    }

    func artifactDirectoryURL() -> URL {
        URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent(".accessibility-preflight", isDirectory: true)
            .appendingPathComponent("semantic-integration", isDirectory: true)
            .appendingPathComponent(normalizedAppSlug, isDirectory: true)
    }

    var normalizedAppSlug: String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let lowered = appSlug.lowercased()
        let filtered = lowered.unicodeScalars.map { allowedCharacters.contains($0) ? Character($0) : "-" }
        return String(filtered).replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    func substitutions() -> [String: String] {
        [
            "{{APP_SLUG}}": appSlug,
            "{{APP_ROOT}}": appRoot,
            "{{PROJECT_ROOT}}": projectRoot,
            "{{ARTIFACT_DIR}}": artifactDirectoryURL().path,
            "{{EXPORT_FILENAME}}": "AccessibilityPreflightSemanticExport.swift"
        ]
    }

    func renderTemplate(at url: URL, substitutions: [String: String]) throws -> String {
        var contents = try String(contentsOf: url, encoding: .utf8)
        for (placeholder, value) in substitutions {
            contents = contents.replacingOccurrences(of: placeholder, with: value)
        }
        return contents
    }

    func readmeTemplateURL() -> URL {
        Self.templatesRootURL()
            .appendingPathComponent("ios-semantic-integration", isDirectory: true)
            .appendingPathComponent("README.template.md")
    }

    func exportTemplateURL() -> URL {
        Self.templatesRootURL()
            .appendingPathComponent("ios-semantic-integration", isDirectory: true)
            .appendingPathComponent(templateVariantDirectoryName(), isDirectory: true)
            .appendingPathComponent("AccessibilityPreflightSemanticExport.swift.template")
    }

    func templateVariantDirectoryName() -> String {
        let lowered = appSlug.lowercased()
        if lowered.contains("homefront") {
            return "homefront"
        }

        return "enclave"
    }

    static func templatesRootURL() -> URL {
        let sourceURL = URL(fileURLWithPath: #filePath)
        return sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Templates", isDirectory: true)
    }
}
