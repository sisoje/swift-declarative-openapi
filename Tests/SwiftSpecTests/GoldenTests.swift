import Foundation
import SwiftSpecCore
import Testing

/// Package root derived from this test file's location.
let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // GoldenTests.swift
    .deletingLastPathComponent() // SwiftSpecTests
    .deletingLastPathComponent() // Tests

let petstoreSpecURL = packageRoot.appendingPathComponent("Specs/petstore.yaml")
let museumSpecURL = packageRoot.appendingPathComponent("Specs/museum.yaml")

@Test(arguments: [
    ("Specs/petstore.yaml", "Sources/PetstoreAPI/Petstore.generated.swift"),
    ("Specs/museum.yaml", "Sources/MuseumAPI/Museum.generated.swift"),
    ("Specs/supabase-auth.yaml", "Sources/SupabaseAuthAPI/SupabaseAuth.generated.swift"),
]) func generatorOutputMatchesCheckedInGoldenFile(spec: String, golden: String) throws {
    let yaml = try String(contentsOf: packageRoot.appendingPathComponent(spec), encoding: .utf8)
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)

    let goldenContents = try String(
        contentsOf: packageRoot.appendingPathComponent(golden),
        encoding: .utf8
    )
    #expect(generated == goldenContents)
}
