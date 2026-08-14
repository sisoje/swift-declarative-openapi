import Foundation
import DeclarativeOpenAPI
import Testing

/// Absolute path to the DeclarativeRequests package the generated code targets.
private let declarativeRequestsPath = "/Users/lazar/dev/declarative-requests-swift"

@Test(arguments: ["petstore.yaml", "museum.yaml", "supabase-auth.yaml"])
func generatedCodeCompilesAgainstDeclarativeRequests(spec: String) throws {
    let specURL = packageRoot.appendingPathComponent("Specs/\(spec)")
    let yaml = try String(contentsOf: specURL, encoding: .utf8)
    let generated = try SpecGenerator().generate(yaml: yaml)

    let fileManager = FileManager.default
    let packageDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("declarative-openapi-e2e-\(UUID().uuidString)")
    let sourcesDirectory = packageDirectory.appendingPathComponent("Sources/GeneratedCheck")
    try fileManager.createDirectory(at: sourcesDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: packageDirectory) }

    let manifest = """
    // swift-tools-version: 6.3
    import PackageDescription

    let package = Package(
        name: "GeneratedCheck",
        platforms: [.macOS(.v14)],
        dependencies: [
            .package(path: "\(declarativeRequestsPath)"),
        ],
        targets: [
            .target(
                name: "GeneratedCheck",
                dependencies: [
                    .product(name: "DeclarativeRequests", package: "declarative-requests-swift"),
                ]
            ),
        ]
    )
    """
    try manifest.write(
        to: packageDirectory.appendingPathComponent("Package.swift"),
        atomically: true,
        encoding: .utf8
    )
    try generated.write(
        to: sourcesDirectory.appendingPathComponent("Generated.swift"),
        atomically: true,
        encoding: .utf8
    )

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "build", "--package-path", packageDirectory.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let outputData = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
    process.waitUntilExit()

    let output = String(decoding: outputData, as: UTF8.self)
    #expect(
        process.terminationStatus == 0,
        "swift build of generated code failed (exit \(process.terminationStatus)):\n\(output)"
    )
}
