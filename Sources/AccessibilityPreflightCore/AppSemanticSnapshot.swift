import Foundation

public struct AppSemanticAuditScenario: Codable, Equatable, Sendable {
    public let scenarioID: String
    public let screenID: String
    public let label: String
    public let detail: String?

    public init(
        scenarioID: String,
        screenID: String,
        label: String,
        detail: String? = nil
    ) {
        self.scenarioID = scenarioID
        self.screenID = screenID
        self.label = label
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case scenarioID = "scenario_id"
        case screenID = "screen_id"
        case label
        case detail
    }
}

public struct AppSemanticElement: Codable, Equatable, Sendable {
    public let elementID: String
    public let role: String
    public let label: String?
    public let accessibilityIdentifier: String?
    public let sourceFile: String?
    public let sourceLine: Int?

    public init(
        elementID: String,
        role: String,
        label: String?,
        accessibilityIdentifier: String?,
        sourceFile: String?,
        sourceLine: Int?
    ) {
        self.elementID = elementID
        self.role = role
        self.label = label
        self.accessibilityIdentifier = accessibilityIdentifier
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
    }

    private enum CodingKeys: String, CodingKey {
        case elementID = "element_id"
        case role
        case label
        case accessibilityIdentifier = "accessibility_identifier"
        case sourceFile = "source_file"
        case sourceLine = "source_line"
    }
}

public struct AppSemanticSnapshot: Codable, Equatable, Sendable {
    public let appID: String
    public let platform: String
    public let screenID: String
    public let selectedSection: String?
    public let primaryActions: [String]
    public let statusSummaries: [String]
    public let visibleLabels: [String]
    public let elements: [AppSemanticElement]
    public let auditScenarios: [AppSemanticAuditScenario]
    public let interruptionState: String?
    public let buildScheme: String
    public let capturedAt: Date

    public init(
        appID: String,
        platform: String,
        screenID: String,
        selectedSection: String?,
        primaryActions: [String],
        statusSummaries: [String],
        visibleLabels: [String],
        elements: [AppSemanticElement] = [],
        auditScenarios: [AppSemanticAuditScenario] = [],
        interruptionState: String?,
        buildScheme: String,
        capturedAt: Date
    ) {
        self.appID = appID
        self.platform = platform
        self.screenID = screenID
        self.selectedSection = selectedSection
        self.primaryActions = primaryActions
        self.statusSummaries = statusSummaries
        self.visibleLabels = visibleLabels
        self.elements = elements
        self.auditScenarios = auditScenarios
        self.interruptionState = interruptionState
        self.buildScheme = buildScheme
        self.capturedAt = capturedAt
    }

    private enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case platform
        case screenID = "screen_id"
        case selectedSection = "selected_section"
        case primaryActions = "primary_actions"
        case statusSummaries = "status_summaries"
        case visibleLabels = "visible_labels"
        case elements
        case auditScenarios = "audit_scenarios"
        case interruptionState = "interruption_state"
        case buildScheme = "build_scheme"
        case capturedAt = "captured_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appID = try container.decode(String.self, forKey: .appID)
        platform = try container.decode(String.self, forKey: .platform)
        screenID = try container.decode(String.self, forKey: .screenID)
        selectedSection = try container.decodeIfPresent(String.self, forKey: .selectedSection)
        primaryActions = try container.decode([String].self, forKey: .primaryActions)
        statusSummaries = try container.decode([String].self, forKey: .statusSummaries)
        visibleLabels = try container.decode([String].self, forKey: .visibleLabels)
        elements = try container.decodeIfPresent([AppSemanticElement].self, forKey: .elements) ?? []
        auditScenarios = try container.decodeIfPresent([AppSemanticAuditScenario].self, forKey: .auditScenarios) ?? []
        interruptionState = try container.decodeIfPresent(String.self, forKey: .interruptionState)
        buildScheme = try container.decode(String.self, forKey: .buildScheme)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
    }
}
