enum SnapshotRules {
    static func finite(_ value: Double?) -> Double? {
        guard let value = value, value.isFinite else { return nil }
        return value
    }

    static func duration(_ value: Duration?) -> Duration? {
        guard let value = value, value >= .zero else { return nil }
        return value
    }
}
