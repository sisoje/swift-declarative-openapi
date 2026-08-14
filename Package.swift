// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "swift-spec",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "swift-spec", targets: ["SwiftSpecCLI"]),
        .library(name: "SwiftSpecCore", targets: ["SwiftSpecCore"]),
        .library(name: "PetstoreAPI", targets: ["PetstoreAPI"]),
        .library(name: "MuseumAPI", targets: ["MuseumAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(path: "../declarative-requests-swift"),
    ],
    targets: [
        .target(
            name: "SwiftSpecCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .executableTarget(
            name: "SwiftSpecCLI",
            dependencies: ["SwiftSpecCore"]
        ),
        .target(
            name: "PetstoreAPI",
            dependencies: [
                .product(name: "DeclarativeRequests", package: "declarative-requests-swift"),
            ]
        ),
        .target(
            name: "MuseumAPI",
            dependencies: [
                .product(name: "DeclarativeRequests", package: "declarative-requests-swift"),
            ]
        ),
        .testTarget(
            name: "SwiftSpecTests",
            dependencies: [
                "SwiftSpecCore",
                "PetstoreAPI",
                "MuseumAPI",
                .product(name: "DeclarativeRequests", package: "declarative-requests-swift"),
            ]
        ),
    ]
)
