// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "WhyUtilsApp",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "whyutils-swift", targets: ["WhyUtilsApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", branch: "release/6.2.2")
    ],
    targets: [
        .executableTarget(
            name: "WhyUtilsApp",
            path: "Sources/WhyUtilsApp"
        ),
        .testTarget(
            name: "WhyUtilsAppTests",
            dependencies: [
                "WhyUtilsApp",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/WhyUtilsAppTests"
        )
    ]
)
