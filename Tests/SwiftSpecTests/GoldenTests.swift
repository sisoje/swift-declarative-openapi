import Foundation
import SwiftSpecCore
import Testing

/// Package root derived from this test file's location.
let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // GoldenTests.swift
    .deletingLastPathComponent() // SwiftSpecTests
    .deletingLastPathComponent() // Tests

let petstoreSpecURL = packageRoot.appendingPathComponent("Specs/petstore.yaml")

@Test func generatorOutputMatchesCheckedInGoldenFile() throws {
    let yaml = try String(contentsOf: petstoreSpecURL, encoding: .utf8)
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)

    let goldenURL = packageRoot.appendingPathComponent("Sources/PetstoreAPI/Petstore.generated.swift")
    let golden = try String(contentsOf: goldenURL, encoding: .utf8)

    #expect(generated == golden)
}
