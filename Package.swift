// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Panes",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "Panes",
            targets: ["Panes"]
        )
    ],
    dependencies: [
        // ZIPファイル読み込み用
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
        // Swift Testing フレームワーク
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Panes",
            dependencies: ["ZIPFoundation"],
            path: "Sources/Panes",
            resources: [
                .process("../../Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "PanesTests",
            dependencies: [
                "Panes",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/PanesTests"
        )
    ]
)
