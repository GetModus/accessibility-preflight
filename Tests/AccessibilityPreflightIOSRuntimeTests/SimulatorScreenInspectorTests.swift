import XCTest
@testable import AccessibilityPreflightIOSRuntime
import CoreGraphics

final class SimulatorScreenInspectorTests: XCTestCase {
    func testAnalyzeFiltersStatusBarAndPermissionDialogNoise() {
        let result = SimulatorScreenInspector.analyze(
            observations: [
                VisibleTextObservation(text: "7:05", frame: CGRect(x: 20, y: 8, width: 60, height: 18)),
                VisibleTextObservation(text: "\"Enclave\" Would Like to Send", frame: CGRect(x: 40, y: 180, width: 260, height: 24)),
                VisibleTextObservation(text: "You Notifications", frame: CGRect(x: 60, y: 210, width: 220, height: 20)),
                VisibleTextObservation(text: "Notifications may include alerts,", frame: CGRect(x: 44, y: 240, width: 280, height: 20)),
                VisibleTextObservation(text: "Don't Allow", frame: CGRect(x: 48, y: 320, width: 120, height: 22)),
                VisibleTextObservation(text: "Allow", frame: CGRect(x: 200, y: 320, width: 80, height: 22)),
                VisibleTextObservation(text: "Home", frame: CGRect(x: 24, y: 520, width: 90, height: 26)),
                VisibleTextObservation(text: "Continue", frame: CGRect(x: 24, y: 568, width: 140, height: 26))
            ],
            screenshotPath: "/tmp/default.png"
        )

        XCTAssertEqual(result.recognizedTexts, ["Home", "Continue"])
        XCTAssertEqual(result.readingOrder, ["Home", "Continue"])
        XCTAssertTrue(result.duplicateCommandNames.isEmpty)
    }

    func testAnalyzeDropsLowSignalFragments() {
        let result = SimulatorScreenInspector.analyze(
            observations: [
                VisibleTextObservation(text: "C", frame: CGRect(x: 24, y: 120, width: 12, height: 14)),
                VisibleTextObservation(text: ":03", frame: CGRect(x: 44, y: 120, width: 28, height: 14)),
                VisibleTextObservation(text: "Go", frame: CGRect(x: 24, y: 180, width: 40, height: 20)),
                VisibleTextObservation(text: "Settings", frame: CGRect(x: 24, y: 220, width: 100, height: 22))
            ],
            screenshotPath: "/tmp/default.png"
        )

        XCTAssertEqual(result.recognizedTexts, ["Go", "Settings"])
        XCTAssertEqual(result.readingOrder, ["Go", "Settings"])
    }

    func testAnalyzeDetectsDuplicateCommandNamesAndReadingOrder() {
        let result = SimulatorScreenInspector.analyze(
            observations: [
                VisibleTextObservation(text: "Continue", frame: CGRect(x: 20, y: 20, width: 100, height: 20)),
                VisibleTextObservation(text: "Settings", frame: CGRect(x: 20, y: 60, width: 100, height: 20)),
                VisibleTextObservation(text: "Continue", frame: CGRect(x: 200, y: 60, width: 100, height: 20))
            ],
            screenshotPath: "/tmp/default.png"
        )

        XCTAssertEqual(result.duplicateCommandNames, ["Continue"])
        XCTAssertEqual(result.readingOrder.prefix(3), ["Continue", "Settings", "Continue"])
        XCTAssertEqual(result.screenshotPath, "/tmp/default.png")
    }

    func testAnalyzeFlagsTruncationAndCrowdedTextRegions() {
        let result = SimulatorScreenInspector.analyze(
            observations: [
                VisibleTextObservation(text: "Very long account settin…", frame: CGRect(x: 20, y: 20, width: 180, height: 24)),
                VisibleTextObservation(text: "Permission", frame: CGRect(x: 20, y: 48, width: 120, height: 22)),
                VisibleTextObservation(text: "Permission details", frame: CGRect(x: 28, y: 50, width: 140, height: 22))
            ],
            screenshotPath: "/tmp/dynamic.png"
        )

        XCTAssertEqual(result.truncationCandidates, ["Very long account settin…"])
        XCTAssertEqual(result.crowdedTextPairs.count, 1)
        XCTAssertTrue(result.crowdedTextPairs[0].contains("Permission"))
    }
}
