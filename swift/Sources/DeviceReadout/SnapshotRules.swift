enum SnapshotRules {
    static func finite(_ value: Double?) -> Double? {
        guard let value = value, value.isFinite else { return nil }
        return value
    }

    static func ratio(_ value: Double?) -> Double? {
        guard let value = finite(value), (0...1).contains(value) else { return nil }
        return value
    }

    static func duration(_ value: Duration?) -> Duration? {
        guard let value = value, value >= .zero else { return nil }
        return value
    }

    static func rectangle(_ value: Rect?) -> Rect? {
        guard let value = value, value.x.isFinite, value.y.isFinite,
              value.width.isFinite, value.height.isFinite else { return nil }
        return value
    }

    static func insets(_ value: Insets?) -> Insets? {
        guard let value = value, value.top.isFinite, value.right.isFinite,
              value.bottom.isFinite, value.left.isFinite else { return nil }
        return value
    }

    static func size(_ value: Size<Double>?) -> Size<Double>? {
        guard let value = value, value.width.isFinite, value.height.isFinite else { return nil }
        return value
    }

    static func vector(_ value: Vector3?) -> Vector3? {
        guard let value = value, value.x.isFinite, value.y.isFinite, value.z.isFinite else { return nil }
        return value
    }

    static func rotation(_ value: Quaternion?) -> Quaternion? {
        guard let value = value, value.x.isFinite, value.y.isFinite,
              value.z.isFinite, value.w.isFinite else { return nil }
        let scale = max(max(abs(value.x), abs(value.y)), max(abs(value.z), abs(value.w)))
        guard scale > 0 else { return nil }
        // Scale before squaring so finite huge and subnormal rotations retain their direction.
        let x = value.x / scale, y = value.y / scale, z = value.z / scale, w = value.w / scale
        let length = (x * x + y * y + z * z + w * w).squareRoot()
        return Quaternion(x: x / length, y: y / length, z: z / length, w: w / length)
    }

    static func displayMode(_ value: DisplayMode?) -> DisplayMode? {
        value.map(normalizedMode)
    }

    static func displayModes(_ values: [DisplayMode]?) -> [DisplayMode]? {
        values?.map(normalizedMode)
    }

    private static func normalizedMode(_ value: DisplayMode) -> DisplayMode {
        DisplayMode(pixelSize: value.pixelSize, refreshRateHz: finite(value.refreshRateHz))
    }
}
