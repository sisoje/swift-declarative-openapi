# swift-spec

An executable that takes an OpenAPI 3.0 YAML spec and generates a **compilable Swift enum** that models every endpoint using the [DeclarativeRequests](../declarative-requests-swift) result-builder DSL. Models are deliberately generated as **fake/minimal stubs** (empty `Codable` structs) — the point is the endpoint surface, not the schemas.

Two reference specs are checked in, both byte-exact canonical files from their upstream repositories:

- `Specs/petstore.yaml` — the classic [petstore](https://learn.openapis.org/examples/v3.0/petstore.html) example (OpenAPI 3.0).
- `Specs/museum.yaml` — the [Redocly Museum API](https://github.com/Redocly/museum-openapi-example) example (OpenAPI 3.1), which exercises `$ref` parameters, scalar/enum component schemas, `allOf`, nested paths (`/tickets/{ticketId}/qr`), and a `webhooks` section (ignored — webhooks aren't client-callable endpoints).
- `Specs/supabase-auth.yaml` — the [Supabase Auth REST API](https://github.com/supabase/auth) (OpenAPI 3.0.3, ~60 operations), which exercises the no-`operationId` fallback naming (`postToken`, `getUser`, …) and templated server URLs (`https://{project}.supabase.co/auth/v1` — emitted as a doc comment, not a `defaultBaseURL`, since a template isn't a resolvable URL). `Sources/SupabaseAuthAPI` additionally carries a **hand-written wiring layer** (`SupabaseAuthWiring.swift`) on top of the generated enum: `keyed(apikey:)` / `authorized(accessToken:)` modifiers, and a **token-refresh** builder — `refreshSession(refreshToken:)` rides the generated `postToken` case for method/path/query and lays the real `{"refresh_token": …}` payload over the stub body (blocks apply in order, so the later `RequestBody.json` wins).

## Usage

```sh
swift run swift-spec Specs/petstore.yaml                 # generated Swift on stdout
swift run swift-spec Specs/petstore.yaml -o Petstore.swift
swift run swift-spec Specs/petstore.yaml --enum-name MyAPI
```

Flags: `-o`/`--output <file>`, `--enum-name <Name>` (overrides the name derived from `info.title`), `-h`/`--help`. Missing/unreadable input or invalid YAML produces a clear error on stderr and exit code 1.

## What it generates

For the petstore spec the output is exactly `Sources/PetstoreAPI/Petstore.generated.swift`:

```swift
struct APIError: Codable {}
struct Pet: Codable {}
typealias Pets = [Pet]

enum SwaggerPetstoreEndpoint: RequestBuildable {
    case listPets(limit: Int?)
    case createPets(body: Pet)
    case showPetById(petId: String)

    static let defaultBaseURL = URL(string: "http://petstore.swagger.io/v1")

    @RequestBuilder var body: some RequestBuildable {
        switch self {
        case let .listPets(limit):
            Method.GET
            Endpoint("pets")
            if let limit {
                Query("limit", String(limit))
            }
        ...
    }
}
```

Consuming it is plain DeclarativeRequests:

```swift
let request = try SwaggerPetstoreEndpoint.showPetById(petId: "42")
    .base(SwaggerPetstoreEndpoint.defaultBaseURL!)
    .request
// http://petstore.swagger.io/v1/pets/42, GET
```

### Generation rules

- One enum case per operation, named from `operationId` (camelCase-sanitized); falls back to method + path (e.g. `getPetsPetId`) when `operationId` is missing.
- Path params are interpolated into `Endpoint(...)`; leading `/` is stripped because `Endpoint` paths are joined onto the base URL by `.base(url)`. Path-item-level `parameters` are merged into each operation (operation-level entries win by `(name, in)`).
- Query params: required → `Query("name", value)`; optional → wrapped in `if let`; non-`String` types stringified via `String(...)`; array-typed params emit a `for` loop of repeated `Query` blocks (the DSL's `buildArray`).
- `requestBody` (application/json): `$ref` → associated value of that model type + `RequestBody.json(body)`; inline schemas get a generated `<OperationId>Body` stub.
- Parameters written as `$ref: "#/components/parameters/X"` are resolved to their component definitions (unresolvable refs are dropped).
- `security:` declarations generate the README's Open Spec auth concept per case: `var securitySchemes: Set<String>` (operation-level overrides the document default; `security: []` marks an operation public; OR-alternatives are flattened), `var needsAuth: Bool`, and one named flag per scheme the spec uses — `needsUserAuth`, `needsAdminAuth`, `needsAPIKeyAuth`, … Omitted entirely when the spec declares no security. Wiring layers gate on the named flags — see `SupabaseAuthWiring.swift`: all auth modifiers take optionals; `authorized(accessToken:)` applies the bearer only where `needsUserAuth` and throws `MissingAccessToken` when a required token is nil, `admin(serviceRoleToken:)` does the same for `needsAdminAuth` (user/SSO-provider management), and `keyed(apikey: nil)` omits the header.
- `components.schemas`: `object` (or `allOf`) → empty `struct X: Codable {}`, `array` → `typealias X = [Element]`, scalars → `typealias X = String/Int/Double/Bool` (`format: binary` → `Data`). Names are sanitized to valid Swift identifiers (`thing-request` → `ThingRequest`); names that would shadow stdlib types are prefixed (`Error` → `APIError`, `Date` → `APIDate`).
- Type mapping: `string`→`String`, `integer`→`Int`, `number`→`Double`, `boolean`→`Bool`, `array`→`[Element]`, `$ref`→model type.
- `servers[0].url` becomes `static let defaultBaseURL`. Header/cookie params are not generated (a `// TODO:` comment is emitted in the case instead). Specs with zero operations still produce compiling output (placeholder body instead of an illegal empty `switch`).
- Output is deterministic (schemas alphabetical, paths sorted, fixed method order) so it's golden-testable.

## Package layout

- `Sources/SwiftSpecCore` — all parsing (via [Yams](https://github.com/jpsim/Yams)) and codegen; `SwiftSpecGenerator(enumNameOverride:).generate(yaml:) -> String`.
- `Sources/SwiftSpecCLI` — the `swift-spec` executable (plain `CommandLine.arguments`, no argument-parser dependency).
- `Sources/PetstoreAPI`, `Sources/MuseumAPI`, and `Sources/SupabaseAuthAPI` — the **checked-in generated outputs** (plus the hand-written Supabase wiring), compiled against DeclarativeRequests on every `swift build`, so compilability of generated code is proven by the build itself.
- `Specs/` — the canonical spec files.
- `Tests/SwiftSpecTests` — 38 tests:
  - **E2E generate-then-compile** (parameterized over all three specs): generates from the spec, writes a fresh temp SwiftPM package depending on DeclarativeRequests, runs a real `swift build` there, and asserts exit 0 (compiler output is surfaced on failure).
  - **Golden** (parameterized over all three specs): generator output must equal the checked-in `*.generated.swift` byte-for-byte.
  - **Request shape**: builds actual `URLRequest`s from the generated enums and asserts URLs, methods, query items, headers, and JSON bodies — including the Supabase refresh flow (`POST …/token?grant_type=refresh_token` with the real refresh-token payload and `apikey` header).
  - **Unit**: name sanitization, type mapping, slash stripping, required/optional/array query params, operationId fallback, enum-name override, header-param TODOs, invalid-YAML errors.

## Notes & caveats

- Models are empty stubs by design — `Pet()` encodes/decodes nothing. Swap in real properties whenever needed.
- Requires the sibling checkout `../declarative-requests-swift` (relative path dependency in `Package.swift`). The e2e test additionally references it by **absolute path** (`/Users/lazar/dev/declarative-requests-swift`), so the test suite is machine-local as-is.
- Toolchain: swift-tools-version 6.3, macOS 14+ (matching the DSL package). First build fetches Yams from the network.
- The initial implementation was hardened by an adversarial review pass that caught and fixed: ignored path-item-level `parameters` (literal `{petId}` left in URLs), unsanitized schema names, non-compiling `String([T])` for array params, empty-`switch` output for operation-less specs, and the `Error` schema shadowing `Swift.Error`.
