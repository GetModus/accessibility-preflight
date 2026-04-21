import XCTest
@testable import AccessibilityPreflightBuild

final class XcodeBuilderTests: XCTestCase {
    func testCommandRunnerMergesInvocationEnvironmentIntoProcess() throws {
        let result = try ProcessCommandRunner.run(
            CommandInvocation(
                executable: "/usr/bin/env",
                arguments: [],
                workingDirectory: nil,
                environment: ["ACCESSIBILITY_PREFLIGHT_TEST_ENV": "merged"]
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("ACCESSIBILITY_PREFLIGHT_TEST_ENV=merged"))
    }

    func testBuildSelectsApplicationTargetFromBuildSettings() throws {
        var invocations: [CommandInvocation] = []
        let settingsJSON = """
        [
          {
            "buildSettings" : {
              "TARGET_BUILD_DIR" : "/tmp/Derived/Build/Products/Debug",
              "WRAPPER_NAME" : "WrongApp.app",
              "PRODUCT_BUNDLE_IDENTIFIER" : "com.demo.wrong",
              "EXECUTABLE_PATH" : "WrongApp.app/Contents/MacOS/WrongApp"
            }
          },
          {
            "buildSettings" : {
              "TARGET_BUILD_DIR" : "/tmp/Derived/Build/Products/Debug",
              "WRAPPER_NAME" : "Demo.app",
              "PRODUCT_BUNDLE_IDENTIFIER" : "com.demo.app",
              "EXECUTABLE_PATH" : "Demo.app/Contents/MacOS/Demo"
            }
          }
        ]
        """

        let result = try XcodeBuilder.build(
            target: ResolvedBuildTarget(
                projectName: "Demo.xcodeproj",
                projectPath: "/tmp/Project/Demo.xcodeproj",
                containerKind: .project,
                containerName: "Demo.xcodeproj",
                containerPath: "/tmp/Project/Demo.xcodeproj",
                schemeName: "Demo",
                buildableName: "Demo.app"
            ),
            destination: "platform=macOS",
            derivedDataPath: "/tmp/Derived",
            commandRunner: { invocation in
                invocations.append(invocation)
                if invocation.arguments.contains("-showBuildSettings") {
                    return CommandResult(stdout: settingsJSON, stderr: "", exitCode: 0)
                }

                return CommandResult(stdout: "** BUILD SUCCEEDED **", stderr: "", exitCode: 0)
            },
            fileExists: { _ in true }
        )

        XCTAssertEqual(result.scheme, "Demo")
        XCTAssertEqual(result.buildPath, "/tmp/Derived/Build/Products/Debug/Demo.app")
        XCTAssertEqual(result.executablePath, "/tmp/Derived/Build/Products/Debug/Demo.app/Contents/MacOS/Demo")
        XCTAssertEqual(result.bundleIdentifier, "com.demo.app")
        XCTAssertEqual(invocations.count, 2)
        XCTAssertTrue(invocations[0].arguments.contains("-showBuildSettings"))
        XCTAssertEqual(invocations[1].arguments.last, "build")
    }

    func testBuildUsesWorkspaceArgumentsForWorkspaceTargets() throws {
        var invocations: [CommandInvocation] = []
        let settingsJSON = """
        [
          {
            "buildSettings" : {
              "TARGET_BUILD_DIR" : "/tmp/Derived/Build/Products/Debug-iphonesimulator",
              "WRAPPER_NAME" : "Demo.app",
              "PRODUCT_BUNDLE_IDENTIFIER" : "com.demo.app",
              "EXECUTABLE_PATH" : "Demo.app/Demo"
            }
          }
        ]
        """

        _ = try XcodeBuilder.build(
            target: ResolvedBuildTarget(
                projectName: "Demo.xcodeproj",
                projectPath: "/tmp/Project/Demo.xcodeproj",
                containerKind: .workspace,
                containerName: "Demo.xcworkspace",
                containerPath: "/tmp/Project/Demo.xcworkspace",
                schemeName: "Demo",
                buildableName: "Demo.app"
            ),
            destination: "platform=iOS Simulator,id=device",
            derivedDataPath: "/tmp/Derived",
            commandRunner: { invocation in
                invocations.append(invocation)
                if invocation.arguments.contains("-showBuildSettings") {
                    return CommandResult(stdout: settingsJSON, stderr: "", exitCode: 0)
                }

                return CommandResult(stdout: "** BUILD SUCCEEDED **", stderr: "", exitCode: 0)
            },
            fileExists: { _ in true }
        )

        XCTAssertEqual(invocations.count, 2)
        XCTAssertTrue(invocations[0].arguments.contains("-workspace"))
        XCTAssertTrue(invocations[0].arguments.contains("/tmp/Project/Demo.xcworkspace"))
        XCTAssertFalse(invocations[0].arguments.contains("-project"))
        XCTAssertTrue(invocations[1].arguments.contains("-workspace"))
    }
}
