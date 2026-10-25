// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskGear",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DeskGearKit", targets: ["DeskGearKit"]),
        .executable(name: "deskgear", targets: ["deskgear"]),
        .executable(name: "DeskGearApp", targets: ["DeskGearApp"]),
    ],
    targets: [
        .target(name: "DeskGearKit"),
        .executableTarget(name: "deskgear", dependencies: ["DeskGearKit"]),
        .executableTarget(name: "DeskGearApp", dependencies: ["DeskGearKit"]),
        .testTarget(name: "DeskGearKitTests", dependencies: ["DeskGearKit"]),
    ]
)
