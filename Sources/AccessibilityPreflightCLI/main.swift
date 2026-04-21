import Foundation

do {
    let result = try await executeCLI(arguments: Array(CommandLine.arguments.dropFirst()))
    print(result.output)
    exit(Int32(result.exitCode))
} catch {
    FileHandle.standardError.write(Data("accessibility-preflight: \(error)\n".utf8))
    exit(1)
}
