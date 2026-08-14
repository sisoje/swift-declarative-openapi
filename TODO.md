# TODO

Future work for the generator, roughly in value order.

## Multipart / file-upload example and codegen

Neither checked-in spec uses `multipart/form-data` — the DSL's `RequestBody.multipart` support is unexercised. Add a third spec with an upload endpoint (petstore-expanded style `POST /pets/{petId}/photo`) and teach the generator to map `multipart/form-data` request bodies to a `RequestBody.multipart { ... }` block with `Data` associated values for `format: binary` fields.

## Header and cookie parameters

Currently skipped with a `// TODO:` comment in the generated case. The DSL supports arbitrary headers (`Header.custom(name).setValue(value)`), so header params could become associated values wired to that block. Cookie params likewise via `Cookie(name, value)`.

## E2E test portability

`Tests/DeclarativeOpenAPITests/E2ETests.swift` references the DSL by absolute path (`/Users/lazar/dev/declarative-requests-swift`), so the e2e test is machine-local. Derive it from `packageRoot.appendingPathComponent("../declarative-requests-swift")` instead so any machine with the sibling checkout can run the suite.

## Optional-query codegen simplification (blocked on DSL decision)

If the DSL adopts omit-on-nil for nil-valued `Query` (see `../declarative-requests-swift/TODO.md`), the generator can pass typed optionals straight through (`Query("limit", limit)`) and drop the `if let` wrapping entirely.

## Form-urlencoded request bodies

Supabase's `/saml/acs` posts `application/x-www-form-urlencoded`; the generator only maps `application/json`, so that case silently gets no body. Map form bodies to `RequestBody.urlEncoded(name, value)` per field (the DSL accumulates them across blocks).

## Server-variable base URL helper

For templated server URLs (`https://{project}.supabase.co/auth/v1`) the generator now emits a doc comment. It could additionally emit `static func baseURL(project: String) -> URL?` from the declared server variables.

## Security AND/OR structure

`securitySchemes` flattens OR-alternatives (`[{A,B},{C}]` = "(A and B) or C") into one set. Fine for the checked-in specs; a `securityAlternatives: [[String]]` would preserve the structure if a spec ever needs it.

## `needs<Scheme>` name collisions

Two raw scheme names could PascalCase to the same property name (`user-auth` and `UserAuth`). Dedupe or disambiguate if it ever occurs.

## OpenAPI 3.1 nullable types

3.1 allows `type: [string, "null"]` arrays. The tolerant walker currently falls back to `String`; mapping them to optionals would be more faithful. Neither checked-in spec uses this yet.

## Enum hard tail

Handled: string-enum parameters (nested in the endpoint enum), named string-enum schemas, inline property enums (nested in their struct), digit-leading values (`_1080p`). Not handled: integer enums (stay unconstrained `Int`), arrays of enums (items stay `[String]`), and unknown-case decode tolerance if enums ever appear in response models.

## Model-generation hard tail

Model generation covers the easy tier (properties/required, `allOf` flattening, CodingKeys). Deliberately skipped, in rough order of likely need: inline object properties (currently fall back to `String` via the tolerant type mapper — should at least emit a TODO comment), `format` refinements (`uuid` → `UUID`, `date-time` → `Date`), `additionalProperties` → dictionaries, `oneOf`/`anyOf` with discriminators, recursive schemas (need boxing), merge-patch three-state optionality.
