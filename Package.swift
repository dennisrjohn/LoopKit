// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "Shared",
    platforms: [
        .iOS(.v10),
    ],
    products: [
        .library(
            name: "LoopKit",
            targets: ["Shared"]),
        .library(
            name: "LoopKitUI",
            targets: ["Shared"]),
        .library(
            name: "MockKit",
            targets: ["Shared"]),
        .library(
            name: "MockKitUI",
            targets: ["Shared"]),
        .library(
            name: "LoopTestingKit",
            targets: ["Shared"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Shared",
            dependencies: [],
            path: "LoopKit")
    ]
)
