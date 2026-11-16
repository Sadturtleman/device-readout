// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeviceReadout",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "DeviceReadout", targets: ["DeviceReadout"])],
    targets: [
        .target(name: "DeviceReadout"),
        .testTarget(name: "DeviceReadoutTests", dependencies: ["DeviceReadout"]),
    ]
)
