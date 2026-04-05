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
    targets: [
        .executableTarget(
            name: "WhyUtilsApp",
            path: "Sources/WhyUtilsApp"
        ),
        .testTarget(
            name: "WhyUtilsAppTests",
            dependencies: ["WhyUtilsApp"],
            path: "Tests/WhyUtilsAppTests"
        )
    ]
)
