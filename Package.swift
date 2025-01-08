// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ProjectManager",
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
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-enable-private-imports",
                    "-suppress-warnings",
                ])
            ]
        )
    ]
)
