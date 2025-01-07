// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ProjectManager",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "ProjectManager",
            targets: ["ProjectManager"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ProjectManager",
            dependencies: [],
            path: "Sources/ProjectManager"
        )
    ]
) 
