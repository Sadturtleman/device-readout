// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeviceReadoutNativeConsumer",
    platforms: [.iOS(.v16), .macOS(.v13)],
    dependencies: [.package(path: "../../swift")],
    targets: [.executableTarget(name: "NativeConsumer", dependencies: [.product(name: "DeviceReadout", package: "swift")])]
)
