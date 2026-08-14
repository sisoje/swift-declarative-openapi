# TODO

Future work for the generator, roughly in value order.

## Multipart / file-upload example and codegen

Neither checked-in spec uses `multipart/form-data` — the DSL's `RequestBody.multipart` support is unexercised. Add a third spec with an upload endpoint (petstore-expanded style `POST /pets/{petId}/photo`) and teach the generator to map `multipart/form-data` request bodies to a `RequestBody.multipart { ... }` block with `Data` associated values for `format: binary` fields.

## Header and cookie parameters

Currently skipped with a `// TODO:` comment in the generated case. The DSL supports arbitrary headers (`Header.custom(name).setValue(value)`), so header params could become associated values wired to that block. Cookie params likewise via `Cookie(name, value)`.

## E2E test portability

`Tests/SwiftSpecTests/E2ETests.swift` references the DSL by absolute path (`/Users/lazar/dev/declarative-requests-swift`), so the e2e test is machine-local. Derive it from `packageRoot.appendingPathComponent("../declarative-requests-swift")` instead so any machine with the sibling checkout can run the suite.

## Optional-query codegen simplification (blocked on DSL decision)

If the DSL adopts omit-on-nil for nil-valued `Query` (see `../declarative-requests-swift/TODO.md`), the generator can pass typed optionals straight through (`Query("limit", limit)`) and drop the `if let` wrapping entirely.

## Form-urlencoded request bodies

Supabase's `/saml/acs` posts `application/x-www-form-urlencoded`; the generator only maps `application/json`, so that case silently gets no body. Map form bodies to `RequestBody.urlEncoded(name, value)` per field (the DSL accumulates them across blocks).

## Security schemes → auth metadata

Supabase declares `security:` per operation (`APIKeyAuth`, bearer). The generator could emit a `needsAuth`-style computed property (the DSL README's Open Spec pattern) so hand-written wiring layers can gate tokens per case instead of maintaining the mapping by hand.

## Server-variable base URL helper

For templated server URLs (`https://{project}.supabase.co/auth/v1`) the generator now emits a doc comment. It could additionally emit `static func baseURL(project: String) -> URL?` from the declared server variables.

## Enum-typed string parameters

`grant_type` is an enum of five values in the spec but generates as `String`. A generated nested `enum GrantType: String` per enum parameter would make invalid values unrepresentable.

## OpenAPI 3.1 nullable types

3.1 allows `type: [string, "null"]` arrays. The tolerant walker currently falls back to `String`; mapping them to optionals would be more faithful. Neither checked-in spec uses this yet.

## Real model generation (opt-in)

Models are empty stubs by design. An opt-in flag (`--models full`) could emit real Codable properties from `properties`/`required`, including `allOf` flattening — kept out of the default per the original brief.
