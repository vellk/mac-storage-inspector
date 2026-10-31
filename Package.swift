// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacStorageInspector",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StorageCore", targets: ["StorageCore"]),
        .executable(name: "MacStorageInspector", targets: ["MacStorageInspector"])
    ],
    targets: [
        .target(name: "StorageCore"),
        .executableTarget(
            name: "MacStorageInspector",
            dependencies: ["StorageCore"]
        ),
        .executableTarget(name: "StorageCoreCheck", dependencies: ["StorageCore"]),
        .testTarget(name: "StorageCoreTests", dependencies: ["StorageCore"])
    ],
    swiftLanguageModes: [.v5]
)
