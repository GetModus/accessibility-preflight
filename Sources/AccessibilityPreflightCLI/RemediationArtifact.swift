import Foundation
import AccessibilityPreflightCore
import AccessibilityPreflightReport

struct RemediationArtifact {
    let project: DiscoveredProject
    let report: Report
    let fileManager: FileManager

    init(project: DiscoveredProject, report: Report, fileManager: FileManager = .default) {
        self.project = project
        self.report = report
        self.fileManager = fileManager
    }

    func generate() throws -> String {
        let draft = try patchDraft()
        let directoryURL = artifactDirectoryURL()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        try readmeContents(draft: draft).write(
            to: directoryURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let manifestData = try JSONEncoder.remediationManifestEncoder.encode(manifest(draft: draft))
        try manifestData.write(to: directoryURL.appendingPathComponent("manifest.json"))

        try draft.contents.write(
            to: directoryURL.appendingPathComponent("changes.patch"),
            atomically: true,
            encoding: .utf8
        )

        return directoryURL.path
    }
}

struct RemediationArtifactApplier {
    let artifactPath: String
    let branchName: String

    func apply() throws -> String {
        let artifactURL = URL(fileURLWithPath: artifactPath, isDirectory: true)
        let manifest = try loadManifest(from: artifactURL)
        guard manifest.patchStatus == "generated" else {
            throw RemediationArtifactError.unsynthesizedPatch(artifactURL.path)
        }

        let patchURL = artifactURL.appendingPathComponent("changes.patch")
        guard FileManager.default.fileExists(atPath: patchURL.path) else {
            throw RemediationArtifactError.missingPatch(patchURL.path)
        }

        try runGit(["switch", "-c", branchName], in: manifest.projectRoot)
        try runGit(["apply", patchURL.path], in: manifest.projectRoot)

        return """
        Applied remediation artifact from \(artifactURL.path)
        Branch: \(branchName)
        Project root: \(manifest.projectRoot)
        Review the working tree, then commit and open a PR when ready.
        """
    }
}

private extension RemediationArtifact {
    func artifactDirectoryURL() -> URL {
        URL(fileURLWithPath: project.rootPath, isDirectory: true)
            .appendingPathComponent(".accessibility-preflight", isDirectory: true)
            .appendingPathComponent("remediation", isDirectory: true)
            .appendingPathComponent(normalizedProjectSlug, isDirectory: true)
    }

    var normalizedProjectSlug: String {
        let baseName = URL(fileURLWithPath: project.projectName).deletingPathExtension().lastPathComponent.lowercased()
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let filtered = baseName.unicodeScalars.map { allowedCharacters.contains($0) ? Character($0) : "-" }
        return String(filtered)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    func actionableFindings() -> [Finding] {
        report.findings.filter { $0.severity == .warn || $0.severity == .critical }
    }

    func patchDraft() throws -> PatchDraft {
        let actionable = actionableFindings()
        let groupedByFile = Dictionary(grouping: actionable.compactMap { finding -> (String, Finding)? in
            guard let file = finding.file else {
                return nil
            }
            return (file, finding)
        }, by: \.0).mapValues { pairs in
            pairs.map(\.1)
        }

        var touchedFiles: [String] = []
        var diffs: [String] = []

        for (filePath, findings) in groupedByFile.sorted(by: { $0.key < $1.key }) {
            guard fileManager.fileExists(atPath: filePath) else {
                continue
            }
            let original = try String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)
            let modified = synthesizeFixes(in: original, for: findings)
            guard modified != original else {
                continue
            }

            let diff = try unifiedDiff(
                originalPath: relativePath(for: filePath),
                modifiedPath: relativePath(for: filePath),
                original: original,
                modified: modified
            )
            guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            touchedFiles.append(filePath)
            diffs.append(diff)
        }

        guard !diffs.isEmpty else {
            return PatchDraft(
                status: "placeholder",
                contents: placeholderPatchContents(
                    touchedFiles: actionable.compactMap(\.file).removingDuplicates().sorted()
                ),
                touchedFiles: actionable.compactMap(\.file).removingDuplicates().sorted()
            )
        }

        return PatchDraft(
            status: "generated",
            contents: diffs.joined(separator: "\n"),
            touchedFiles: touchedFiles
        )
    }

    func manifest(draft: PatchDraft) -> RemediationManifest {
        RemediationManifest(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            projectRoot: project.rootPath,
            projectName: project.projectName,
            platform: project.platform,
            proposalOnly: true,
            patchStatus: draft.status,
            touchedFiles: draft.touchedFiles,
            findingTitles: actionableFindings().map(\.title)
        )
    }

    func readmeContents(draft: PatchDraft) -> String {
        let findingLines = actionableFindings().map {
            "- [\($0.severity.rawValue)] \($0.title)"
        }
        let touchedFiles = draft.touchedFiles.isEmpty
            ? "- no source files were patched automatically"
            : draft.touchedFiles.map { "- \($0)" }.joined(separator: "\n")
        let patchDescription = draft.status == "generated"
            ? "synthesized patch draft for safe fix classes only"
            : "placeholder patch draft; no repository patch could be synthesized automatically yet"

        return """
        # Accessibility Preflight Remediation Proposal

        Warning: this artifact is proposal-only.
        No app code was changed automatically.
        Review everything here before applying any change on a dedicated branch or PR.

        Project root: \(project.rootPath)
        Project: \(project.projectName)
        Platform: \(project.platform)

        Actionable findings:
        \(findingLines.joined(separator: "\n"))

        Files touched by synthesized patch content:
        \(touchedFiles)

        What is in this bundle:
        - `README.md`: review instructions and finding summary
        - `manifest.json`: proposal metadata for tooling or future apply flows
        - `changes.patch`: \(patchDescription)

        Suggested review flow:
        1. Review the findings and the files listed in `manifest.json`.
        2. Inspect `changes.patch` and confirm the synthesized edits match intent.
        3. Apply changes only on a dedicated review branch after approval.
        4. Use `accessibility-preflight apply-artifact --artifact \(artifactDirectoryURL().path) --branch codex/accessibility-review` for generated patches.
        """
    }

    func synthesizeFixes(in source: String, for findings: [Finding]) -> String {
        var modified = source

        if findings.contains(where: { $0.title == "Fixed font point size" }) {
            modified = synthesizeSystemFontFixes(in: modified)
        }

        if findings.contains(where: { $0.title == "Fixed custom font point size" }) {
            modified = synthesizeCustomFontFixes(in: modified)
        }

        if findings.contains(where: { $0.title == "Generic accessibility label" }) {
            modified = synthesizeGenericAccessibilityLabels(in: modified)
        }

        return modified
    }

    func synthesizeSystemFontFixes(in source: String) -> String {
        replacingMatches(in: source, pattern: #"\.font\(\.system\(([^)]*)\)\)"#) { _, captures in
            guard let arguments = captures.first else {
                return nil
            }

            let parsedArguments = parseNamedArguments(arguments)
            guard parsedArguments["size"] != nil else {
                return nil
            }

            let weight = parsedArguments["weight"]
            let design = parsedArguments["design"]

            guard weight != nil || design != nil else {
                return ".font(.body)"
            }

            var replacement = ".font(.system(.body"
            if let design {
                replacement.append(", design: \(design)")
            }
            if let weight {
                replacement.append(", weight: \(weight)")
            }
            replacement.append("))")
            return replacement
        }
    }

    func synthesizeCustomFontFixes(in source: String) -> String {
        replacingMatches(in: source, pattern: #"\.font\(\.custom\(([^)]*)\)\)"#) { _, captures in
            guard let arguments = captures.first else {
                return nil
            }

            guard arguments.contains("size:"), !arguments.contains("relativeTo:") else {
                return nil
            }

            return ".font(.custom(\(arguments), relativeTo: .body))"
        }
    }

    func synthesizeGenericAccessibilityLabels(in source: String) -> String {
        let literalButtonPattern = #"(Button\(\"([^\"]+)\"\)\s*\{[\s\S]*?\})\s*\.accessibilityLabel\(\"(?:Button|Image)\"\)"#
        let closureButtonPattern = #"(Button\s*\{[\s\S]*?\}\s*label:\s*\{\s*Text\(\"([^\"]+)\"\)\s*\})\s*\.accessibilityLabel\(\"(?:Button|Image)\"\)"#

        let afterLiteralButtons = replacingMatches(in: source, pattern: literalButtonPattern) { _, captures in
            guard captures.count >= 2 else {
                return nil
            }

            let buttonExpression = captures[0]
            let title = captures[1]
            return #"\#(buttonExpression).accessibilityLabel("\#(title)")"#
        }

        return replacingMatches(in: afterLiteralButtons, pattern: closureButtonPattern) { _, captures in
            guard captures.count >= 2 else {
                return nil
            }

            let buttonExpression = captures[0]
            let title = captures[1]
            return #"\#(buttonExpression).accessibilityLabel("\#(title)")"#
        }
    }

    func placeholderPatchContents(touchedFiles: [String]) -> String {
        let fileLines = touchedFiles.isEmpty
            ? "# - no source files were identified directly from findings"
            : touchedFiles.map { "# - \($0)" }.joined(separator: "\n")

        return """
        # accessibility-preflight proposal-only patch placeholder
        # No repository changes were applied automatically.
        # No code patch could be synthesized automatically for the current findings.
        # Review README.md and manifest.json, then prepare a branch or PR from the findings below.
        # Candidate files:
        \(fileLines)
        """
    }

    func unifiedDiff(
        originalPath: String,
        modifiedPath: String,
        original: String,
        modified: String
    ) throws -> String {
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let originalURL = tempDirectory.appendingPathComponent("original.swift")
        let modifiedURL = tempDirectory.appendingPathComponent("modified.swift")
        try original.write(to: originalURL, atomically: true, encoding: .utf8)
        try modified.write(to: modifiedURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        process.arguments = [
            "-u",
            "--label", originalPath,
            originalURL.path,
            "--label", modifiedPath,
            modifiedURL.path
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let diffOutput = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw RemediationArtifactError.diffFailed(errorOutput.isEmpty ? diffOutput : errorOutput)
        }

        return diffOutput
    }

    func relativePath(for filePath: String) -> String {
        let rootURL = URL(fileURLWithPath: project.rootPath, isDirectory: true).standardizedFileURL
        let fileURL = URL(fileURLWithPath: filePath).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        if fileURL.path.hasPrefix(rootPath) {
            return String(fileURL.path.dropFirst(rootPath.count))
        }
        return filePath
    }

    func parseNamedArguments(_ arguments: String) -> [String: String] {
        arguments
            .split(separator: ",")
            .reduce(into: [:]) { partialResult, segment in
                let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let separatorIndex = trimmedSegment.firstIndex(of: ":") else {
                    return
                }

                let key = trimmedSegment[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = trimmedSegment[trimmedSegment.index(after: separatorIndex)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                partialResult[key] = value
            }
    }

    func replacingMatches(
        in source: String,
        pattern: String,
        transform: (String, [String]) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return source
        }

        let nsSource = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
        guard !matches.isEmpty else {
            return source
        }

        var result = ""
        var currentLocation = 0

        for match in matches {
            let fullRange = match.range(at: 0)
            result += nsSource.substring(with: NSRange(location: currentLocation, length: fullRange.location - currentLocation))

            let fullText = nsSource.substring(with: fullRange)
            let captures = (1..<match.numberOfRanges).compactMap { index -> String? in
                let range = match.range(at: index)
                guard range.location != NSNotFound else {
                    return nil
                }
                return nsSource.substring(with: range)
            }

            result += transform(fullText, captures) ?? fullText
            currentLocation = fullRange.location + fullRange.length
        }

        result += nsSource.substring(from: currentLocation)
        return result
    }
}

private struct PatchDraft {
    let status: String
    let contents: String
    let touchedFiles: [String]
}

private struct RemediationManifest: Codable {
    let generatedAt: String
    let projectRoot: String
    let projectName: String
    let platform: String
    let proposalOnly: Bool
    let patchStatus: String
    let touchedFiles: [String]
    let findingTitles: [String]

    private enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case projectRoot = "project_root"
        case projectName = "project_name"
        case platform
        case proposalOnly = "proposal_only"
        case patchStatus = "patch_status"
        case touchedFiles = "touched_files"
        case findingTitles = "finding_titles"
    }
}

private enum RemediationArtifactError: LocalizedError {
    case missingManifest(String)
    case missingPatch(String)
    case unsynthesizedPatch(String)
    case gitFailed(String)
    case diffFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest(let path):
            return "Remediation artifact is missing manifest.json at \(path)"
        case .missingPatch(let path):
            return "Remediation artifact is missing changes.patch at \(path)"
        case .unsynthesizedPatch(let path):
            return "Remediation artifact at \(path) does not contain a synthesized patch to apply."
        case .gitFailed(let detail):
            return "Git command failed while applying remediation artifact: \(detail)"
        case .diffFailed(let detail):
            return "Failed to synthesize remediation diff: \(detail)"
        }
    }
}

private extension RemediationArtifactApplier {
    func loadManifest(from artifactURL: URL) throws -> RemediationManifest {
        let manifestURL = artifactURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw RemediationArtifactError.missingManifest(manifestURL.path)
        }

        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(RemediationManifest.self, from: data)
    }
}

private extension JSONEncoder {
    static var remediationManifestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private func runGit(_ arguments: [String], in workingDirectory: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let stdoutText = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let stderrText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw RemediationArtifactError.gitFailed(stderrText.isEmpty ? stdoutText : stderrText)
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
