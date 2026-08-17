// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "swift-declarative-openapi",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .executable(name: "declarative-openapi", targets: ["DeclarativeOpenAPICLI"]),
        .library(name: "DeclarativeOpenAPI", targets: ["DeclarativeOpenAPI"]),
        .library(name: "DeclarativeOpenAPIRuntime", targets: ["DeclarativeOpenAPIRuntime"]),
        .library(name: "PetstoreAPI", targets: ["PetstoreAPI"]),
        .library(name: "MuseumAPI", targets: ["MuseumAPI"]),
        .library(name: "SupabaseAuthAPI", targets: ["SupabaseAuthAPI"]),
        .library(name: "BinanceAPI", targets: ["BinanceAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(path: "../swift-declarative-requests"),
    ],
    targets: [
        .target(
            name: "DeclarativeOpenAPI",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .executableTarget(
            name: "DeclarativeOpenAPICLI",
            dependencies: ["DeclarativeOpenAPI"]
        ),
        .target(
            name: "DeclarativeOpenAPIRuntime"
        ),
        .target(
            name: "PetstoreAPI",
            dependencies: [
                "DeclarativeOpenAPIRuntime",
                .product(name: "DeclarativeRequests", package: "swift-declarative-requests"),
            ]
        ),
        .target(
            name: "MuseumAPI",
            dependencies: [
                "DeclarativeOpenAPIRuntime",
                .product(name: "DeclarativeRequests", package: "swift-declarative-requests"),
            ]
        ),
        .target(
            name: "SupabaseAuthAPI",
            dependencies: [
                "DeclarativeOpenAPIRuntime",
                .product(name: "DeclarativeRequests", package: "swift-declarative-requests"),
            ]
        ),
        .target(
            name: "BinanceAPI",
            dependencies: [
                "DeclarativeOpenAPIRuntime",
                .product(name: "DeclarativeRequests", package: "swift-declarative-requests"),
            ]
        ),
        .testTarget(
            name: "DeclarativeOpenAPITests",
            dependencies: [
                "DeclarativeOpenAPI",
                "PetstoreAPI",
                "MuseumAPI",
                "SupabaseAuthAPI",
                "BinanceAPI",
                "DeclarativeOpenAPIRuntime",
                .product(name: "DeclarativeRequests", package: "swift-declarative-requests"),
            ]
        ),
    ]
)
