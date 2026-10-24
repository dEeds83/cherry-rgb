// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CherryRGB",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CherryRGBKit", targets: ["CherryRGBKit"]),
        .executable(name: "cherryrgb", targets: ["cherryrgb"]),
        .executable(name: "CherryRGBApp", targets: ["CherryRGBApp"]),
    ],
    targets: [
        .target(name: "CherryRGBKit"),
        .executableTarget(name: "cherryrgb", dependencies: ["CherryRGBKit"]),
        .executableTarget(name: "CherryRGBApp", dependencies: ["CherryRGBKit"]),
        .testTarget(name: "CherryRGBKitTests", dependencies: ["CherryRGBKit"]),
    ]
)
