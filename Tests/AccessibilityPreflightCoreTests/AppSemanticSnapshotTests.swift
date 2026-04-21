import XCTest
@testable import AccessibilityPreflightCore

final class AppSemanticSnapshotTests: XCTestCase {
    func testSnapshotDecodesCanonicalPayload() throws {
        let json = """
        {
          "app_id": "com.modus.homefront",
          "platform": "ios",
          "screen_id": "dashboard",
          "selected_section": "Dashboard",
          "primary_actions": ["Dashboard", "Protection"],
          "status_summaries": ["Score 92", "DNS Protection On"],
          "visible_labels": ["HomeFront", "Security score"],
          "interruption_state": "none",
          "build_scheme": "HomeFrontMobile",
          "captured_at": "2026-04-20T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(AppSemanticSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.appID, "com.modus.homefront")
        XCTAssertEqual(snapshot.platform, "ios")
        XCTAssertEqual(snapshot.screenID, "dashboard")
        XCTAssertEqual(snapshot.selectedSection, "Dashboard")
        XCTAssertEqual(snapshot.primaryActions, ["Dashboard", "Protection"])
        XCTAssertEqual(snapshot.statusSummaries, ["Score 92", "DNS Protection On"])
        XCTAssertEqual(snapshot.visibleLabels, ["HomeFront", "Security score"])
        XCTAssertTrue(snapshot.elements.isEmpty)
        XCTAssertTrue(snapshot.auditScenarios.isEmpty)
        XCTAssertEqual(snapshot.interruptionState, "none")
        XCTAssertEqual(snapshot.buildScheme, "HomeFrontMobile")
        XCTAssertEqual(snapshot.capturedAt, ISO8601DateFormatter().date(from: "2026-04-20T12:00:00Z"))
    }

    func testSnapshotDecodesElementBreadcrumbs() throws {
        let json = """
        {
          "app_id": "com.modus.homefront",
          "platform": "ios",
          "screen_id": "dashboard",
          "selected_section": "Dashboard",
          "primary_actions": ["Dashboard", "Protection"],
          "status_summaries": ["Score 92"],
          "visible_labels": ["HomeFront"],
          "elements": [
            {
              "element_id": "dashboard.refresh",
              "role": "button",
              "label": "Refresh",
              "accessibility_identifier": "dashboard.refresh.button",
              "source_file": "HomeFrontMobile/Views/MainTabView.swift",
              "source_line": 327
            }
          ],
          "interruption_state": "none",
          "build_scheme": "HomeFrontMobile",
          "captured_at": "2026-04-20T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(AppSemanticSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.elements.count, 1)
        XCTAssertEqual(snapshot.elements.first?.elementID, "dashboard.refresh")
        XCTAssertEqual(snapshot.elements.first?.role, "button")
        XCTAssertEqual(snapshot.elements.first?.label, "Refresh")
        XCTAssertEqual(snapshot.elements.first?.accessibilityIdentifier, "dashboard.refresh.button")
        XCTAssertEqual(snapshot.elements.first?.sourceFile, "HomeFrontMobile/Views/MainTabView.swift")
        XCTAssertEqual(snapshot.elements.first?.sourceLine, 327)
    }

    func testSnapshotDecodesAuditScenarioCatalog() throws {
        let json = """
        {
          "app_id": "com.modus.aihd",
          "platform": "ios",
          "screen_id": "onboarding.identityHook",
          "selected_section": "Onboarding",
          "primary_actions": ["Keep going"],
          "status_summaries": ["Onboarding step 1 of 8"],
          "visible_labels": ["AiHD", "Keep going"],
          "audit_scenarios": [
            {
              "scenario_id": "onboarding.identityHook",
              "screen_id": "onboarding.identityHook",
              "label": "Onboarding",
              "detail": "Initial onboarding state."
            },
            {
              "scenario_id": "settings.preferences",
              "screen_id": "settings.preferences",
              "label": "Settings",
              "detail": "Appearance preferences tab."
            }
          ],
          "interruption_state": "onboarding",
          "build_scheme": "AiHD",
          "captured_at": "2026-04-20T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(AppSemanticSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.auditScenarios.count, 2)
        XCTAssertEqual(snapshot.auditScenarios.first?.scenarioID, "onboarding.identityHook")
        XCTAssertEqual(snapshot.auditScenarios.first?.screenID, "onboarding.identityHook")
        XCTAssertEqual(snapshot.auditScenarios.first?.label, "Onboarding")
    }

    func testSnapshotEncodesCanonicalKeysWithIso8601Date() throws {
        let snapshot = AppSemanticSnapshot(
            appID: "com.modus.enclave",
            platform: "ios",
            screenID: "onboarding",
            selectedSection: nil,
            primaryActions: ["Continue", "Learn more"],
            statusSummaries: ["Connected"],
            visibleLabels: ["Enclave"],
            elements: [
                AppSemanticElement(
                    elementID: "onboarding.continue",
                    role: "button",
                    label: "Continue",
                    accessibilityIdentifier: "onboarding.continue.button",
                    sourceFile: "Enclave/OnboardingView.swift",
                    sourceLine: 42
                )
            ],
            auditScenarios: [
                AppSemanticAuditScenario(
                    scenarioID: "settings.preferences",
                    screenID: "settings.preferences",
                    label: "Settings",
                    detail: "Preferences screen."
                )
            ],
            interruptionState: "modal",
            buildScheme: "Enclave",
            capturedAt: ISO8601DateFormatter().date(from: "2026-04-20T18:30:00Z")!
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"app_id\":\"com.modus.enclave\""))
        XCTAssertTrue(json.contains("\"build_scheme\":\"Enclave\""))
        XCTAssertTrue(json.contains("\"captured_at\":\"2026-04-20T18:30:00Z\""))
        XCTAssertTrue(json.contains("\"element_id\":\"onboarding.continue\""))
        XCTAssertTrue(json.contains("\"primary_actions\":[\"Continue\",\"Learn more\"]"))
        XCTAssertTrue(json.contains("\"audit_scenarios\":["))
        XCTAssertTrue(json.contains("\"scenario_id\":\"settings.preferences\""))
    }
}
