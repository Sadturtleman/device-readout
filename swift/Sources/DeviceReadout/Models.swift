import Foundation

public protocol DeviceSnapshot: Sendable {
    var collectedAt: Date { get }
}

protocol CollectibleSnapshot: DeviceSnapshot {
    func collected() -> any DeviceSnapshot
}

public struct Size<Value: Equatable & Sendable>: Equatable, Sendable {
    public let width: Value
    public let height: Value
    public init(width: Value, height: Value) { self.width = width; self.height = height }
}
public struct Rect: Equatable, Sendable {
    public let x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
public struct Insets: Equatable, Sendable {
    public let top, right, bottom, left: Double
    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top; self.right = right; self.bottom = bottom; self.left = left
    }
}
public struct Vector3: Equatable, Sendable {
    public let x, y, z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
}
public struct Quaternion: Equatable, Sendable {
    public let x, y, z, w: Double
    public init(x: Double, y: Double, z: Double, w: Double) { self.x = x; self.y = y; self.z = z; self.w = w }
}
public struct DisplayMode: Equatable, Sendable {
    public let pixelSize: Size<Int>?
    public let refreshRateHz: Double?
    public init(pixelSize: Size<Int>? = nil, refreshRateHz: Double? = nil) {
        self.pixelSize = pixelSize; self.refreshRateHz = refreshRateHz
    }
}
public struct IpAddressInfo: Equatable, Sendable {
    public let address: String
    public let prefixLength: Int?
    public init(address: String, prefixLength: Int? = nil) { self.address = address; self.prefixLength = prefixLength }
}
public struct NetworkRoute: Equatable, Sendable {
    public let destination: String
    public let prefixLength: Int?
    public let gateway: String?
    public init(destination: String, prefixLength: Int? = nil, gateway: String? = nil) {
        self.destination = destination; self.prefixLength = prefixLength; self.gateway = gateway
    }
}
public enum ThermalState: Equatable, Sendable {
    case android(AndroidThermalState)
    case apple(AppleThermalState)
}
public enum ErrorCode: String, Sendable {
    case unsupportedEntity, permissionDenied, entityRemoved, readTimeout, readFailed, invalidConfiguration
}
public struct DeviceReadoutError: Error, Equatable, Sendable {
    public let code: ErrorCode
    public let message: String
    public init(_ code: ErrorCode, _ message: String) { self.code = code; self.message = message }
}
enum EntityMode: Sendable { case state, sample, event }
public struct Entity<Snapshot: DeviceSnapshot>: Sendable, Hashable {
    public let kind: EntityKind
    let requiresTarget: Bool
    let mode: EntityMode
    let binding: TargetBinding?

    init(kind: EntityKind, requiresTarget: Bool, mode: EntityMode, binding: TargetBinding? = nil) {
        self.kind = kind; self.requiresTarget = requiresTarget; self.mode = mode; self.binding = binding
    }
}
public struct EntityRequest: Sendable {
    public let kind: EntityKind
    public let targetId: String?
}
public protocol DeviceCollector: Sendable {
    /// Passive operation support. Runs on the worker without reads, subscriptions or prompts.
    func capabilities(_ request: EntityRequest) throws -> EntityCapabilities
    /// Runs on the collection worker. Implementations must not invoke UI getters or permission prompts.
    func read(_ request: EntityRequest) throws -> any DeviceSnapshot
    /// Complete native inventory. Runs on the collection worker without UI getters or prompts.
    func list(_ kind: EntityKind) throws -> [String]
    /// Return only a platform-defined current target, or nil when no selection is available.
    func current(_ kind: EntityKind) throws -> String?
    /// Releases native resources on the collection worker after pending native work returns.
    func close() throws
}

public extension DeviceCollector {
    func capabilities(_ request: EntityRequest) throws -> EntityCapabilities {
        EntityCapabilities(readable: nil, watchable: nil)
    }
    func list(_ kind: EntityKind) throws -> [String] {
        throw DeviceReadoutError(.unsupportedEntity, "This collector does not support target discovery.")
    }
    func current(_ kind: EntityKind) throws -> String? { nil }
    func close() throws { }
}
