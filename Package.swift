// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WeatherCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(name: "WeatherCore", targets: ["WeatherCore"])
    ],
    targets: [
        .target(
            name: "WeatherCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "WeatherCoreTests",
            dependencies: ["WeatherCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
