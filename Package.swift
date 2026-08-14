// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "swift-declarative-openapi",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "declarative-openapi", targets: ["DeclarativeOpenAPICLI"]),
        .library(name: "DeclarativeOpenAPI", targets: ["DeclarativeOpenAPI"]),
        .library(name: "DeclarativeOpenAPIRuntime", targets: ["DeclarativeOpenAPIRuntime"]),
        .library(name: "PetstoreAPI", targets: ["PetstoreAPI"]),
        .library(name: "MuseumAPI", targets: ["MuseumAPI"]),
        .library(name: "SupabaseAuthAPI", targets: ["SupabaseAuthAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(path: "../declarative-requests-swift"),
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
                .product(name: "DeclarativeRequests", package: "declarative-requests-swift"),
            ]
        ),
        .target(
            name: "MuseumAPI",
            dependencies: [
                "DeclarativeOpenAPIRuntime",
                .product(name: "DeclarativeRequests", package: "declarative-requests-swift"),
            ]
        ),
        .target(
            name: "SupabaseAuthAPI",
            dependencies: [
                "DeclarativeOpenAPIRuntime",
                .product(name: "DeclarativeRequests", package: "declarative-requests-swift"),
            ]
        ),
        .testTarget(
            name: "DeclarativeOpenAPITests",
            dependencies: [
                "DeclarativeOpenAPI",
                "PetstoreAPI",
                "MuseumAPI",
                "SupabaseAuthAPI",
                "DeclarativeOpenAPIRuntime",
                .product(name: "DeclarativeRequests", package: "declarative-requests-swift"),
            ]
        ),
    ]
)
