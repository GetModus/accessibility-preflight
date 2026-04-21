public enum Severity: String, Codable, CaseIterable {
    case critical = "CRITICAL"
    case warn = "WARN"
    case info = "INFO"

    public var sortRank: Int {
        switch self {
        case .critical:
            return 3
        case .warn:
            return 2
        case .info:
            return 1
        }
    }
}
