# swift-declarative-openapi

An executable that takes an OpenAPI 3.0 YAML spec and generates a **compilable Swift enum** that models every endpoint using the [DeclarativeRequests](../declarative-requests-swift) result-builder DSL. Models are generated with real `Codable` properties from `properties`/`required`: optionals get `= nil` defaults (so memberwise inits need only the required fields), `allOf` is flattened via `$ref` resolution, and `CodingKeys` is emitted only when a raw name isn't a clean Swift name.

Two reference specs are checked in, both byte-exact canonical files from their upstream repositories:

- `Specs/petstore.yaml` — the classic [petstore](https://learn.openapis.org/examples/v3.0/petstore.html) example (OpenAPI 3.0).
- `Specs/museum.yaml` — the [Redocly Museum API](https://github.com/Redocly/museum-openapi-example) example (OpenAPI 3.1), which exercises `$ref` parameters, scalar/enum component schemas, `allOf`, nested paths (`/tickets/{ticketId}/qr`), and a `webhooks` section (ignored — webhooks aren't client-callable endpoints).
- `Specs/supabase-auth.yaml` — the [Supabase Auth REST API](https://github.com/supabase/auth) (OpenAPI 3.0.3, ~60 operations), which exercises the no-`operationId` fallback naming (`postToken`, `getUser`, …) and templated server URLs (`https://{project}.supabase.co/auth/v1` — emitted as a doc comment, not a `defaultBaseURL`, since a template isn't a resolvable URL). `Sources/SupabaseAuthAPI` additionally carries a **hand-written wiring layer** (`SupabaseAuthWiring.swift`) on top of the generated enum: `keyed(apikey:)` / `authorized(accessToken:needsAuth:)` modifiers, and a **token-refresh** builder — `refreshSession(refreshToken:)` invokes the generated `postToken` case with the generated `PostTokenBody(refreshToken:)` model.

## Usage

```sh
swift run declarative-openapi Specs/petstore.yaml                 # generated Swift on stdout
swift run declarative-openapi Specs/petstore.yaml -o Petstore.swift
swift run declarative-openapi Specs/petstore.yaml --enum-name MyAPI
```

Flags: `-o`/`--output <file>`, `--enum-name <Name>` (overrides the namespace name derived from `info.title`), `--exclude-scheme <Scheme>` (repeatable — drops every operation whose security requires that scheme, e.g. a server-only admin scheme, and records it in the header comment), `-h`/`--help`. Missing/unreadable input or invalid YAML produces a clear error on stderr and exit code 1.

## What it generates

For the petstore spec the output is exactly `Sources/PetstoreAPI/Petstore.generated.swift`:

```swift
struct APIError: Codable {
    var code: Int
    var message: String
}
struct Pet: Codable {
    var id: Int
    var name: String
    var tag: String? = nil
}
typealias Pets = [Pet]

enum SwaggerPetstoreEndpoint: RequestBuildable {
    case listPets(limit: Int?)
    case createPets(body: Pet)
    case showPetById(petId: String)

    static let defaultBaseURL = URL(string: "http://petstore.swagger.io/v1")

    var body: some RequestBuildable {
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
let request = try SwaggerPetstore.Operation.showPetById(petId: "42")
    .base(SwaggerPetstore.defaultBaseURL!)
    .request()
// http://petstore.swagger.io/v1/pets/42, GET
```

### Generation rules

- The output is one namespace enum (from `info.title`) whose sections mirror the OpenAPI document: schemas, `Operation` (a `RequestBuildable` enum — each operation IS a block), `Security`, and the server URL. One `Operation` case per operation, named from `operationId` (camelCase-sanitized); falls back to method + path (e.g. `getPetsPetId`) when `operationId` is missing.
- Path params are interpolated into `Endpoint(...)`; leading `/` is stripped because `Endpoint` paths are joined onto the base URL by `.base(url)`. Path-item-level `parameters` are merged into each operation (operation-level entries win by `(name, in)`).
- Query params: required → `Query("name", value)`; optional → wrapped in `if let`; non-`String` types stringified via `String(...)`; array-typed params emit a `for` loop of repeated `Query` blocks (the DSL's `buildArray`).
- `requestBody` (application/json): `$ref` → associated value of that model type + `RequestBody.json(body)`; inline schemas get a generated `<OperationId>Body` model with real properties.
- Parameters written as `$ref: "#/components/parameters/X"` are resolved to their component definitions (unresolvable refs are dropped).
- `security:` declarations generate the `Security` section (operation-level overrides the document default; `security: []` marks an operation public; OR-alternatives are flattened): `Security.schemes(_ operation:) -> Set<String>`, one `Security.needs<Scheme>(_ operation:)` gate per scheme, and one **attachment factory** per scheme derived from `components.securitySchemes` — `http bearer` → `Security.userAuth(token:)` wrapping `Authorization.bearer`, `apiKey in: header` → `Security.apiKeyAuth(_:)` wrapping `Header.custom(name)`, `http basic` → `Authorization.basic`. Omitted entirely when the spec declares no security. The wiring is a client composing one flat block — see `SupabaseAuthWiring.swift`: `SupabaseAuthClient(baseURL:apikey:accessToken:)` wires session + environment once; `request(_ operation:)` lays the operation, `BaseURL`, and each Security-gated credential into a single `RequestBlock`, throwing the client's own errors (`MissingAPIKey`, `MissingAccessToken`) via `RequestFailure` when a required credential is nil. `refreshSessionRequest(refreshToken:)` covers the refresh flow (the token is that operation's body parameter, optional because no stored token may exist yet). The checked-in Supabase target is **client-only**: generated with `--exclude-scheme AdminAuth`, so server-side operations (user management, SSO provider management — those needing the service-role JWT) are not generated at all.
- `components.schemas`: `object` (or `allOf`, flattened) → `struct X: Codable` with real properties, `array` → `typealias X = [Element]`, scalars → `typealias X = String/Int/Double/Bool` (`format: binary` → `Data`), string enums → `enum X: String, Codable`. Names are sanitized to valid Swift identifiers (`thing-request` → `ThingRequest`); names that would shadow stdlib types are prefixed (`Error` → `APIError`, `Date` → `APIDate`). The rename carries no semantics: `APIError` does **not** conform to `Swift.Error`, because OpenAPI has no way to mark a schema as an error model and we don't infer that from names — apps that want to throw it add `extension APIError: Swift.Error {}` in hand-written code.
- Type mapping: `string`→`String`, `integer`→`Int`, `number`→`Double`, `boolean`→`Bool`, `array`→`[Element]`, `$ref`→model type. String schemas/parameters/properties with `enum:` values generate `enum X: String, Codable` (schemas at top level, parameters nested in the endpoint enum — `grant_type` → `GrantType`, used via `.rawValue` — and object properties nested in their struct, e.g. `PostTokenBody.Provider`); digit-leading values get a `_` prefix (`_1080p`); a parameter name reused with a different value set falls back to `String`.
- `servers[0].url` becomes `static let defaultBaseURL`. Header/cookie params are not generated (a `// TODO:` comment is emitted in the case instead). Specs with zero operations still produce compiling output (placeholder body instead of an illegal empty `switch`).
- Output is deterministic (schemas alphabetical, paths sorted, fixed method order) so it's golden-testable.

## Package layout

- `Sources/DeclarativeOpenAPI` — all parsing (via [Yams](https://github.com/jpsim/Yams)) and codegen; `SpecGenerator(enumNameOverride:).generate(yaml:) -> String`.
- `Sources/DeclarativeOpenAPICLI` — the `swift-declarative-openapi` executable (plain `CommandLine.arguments`, no argument-parser dependency).
- `Sources/PetstoreAPI`, `Sources/MuseumAPI`, and `Sources/SupabaseAuthAPI` — the **checked-in generated outputs** (plus the hand-written Supabase wiring), compiled against DeclarativeRequests on every `swift build`, so compilability of generated code is proven by the build itself.
- `Specs/` — the canonical spec files.
- `Tests/DeclarativeOpenAPITests` — 55 tests:
  - **E2E generate-then-compile** (parameterized over all three specs): generates from the spec, writes a fresh temp SwiftPM package depending on DeclarativeRequests, runs a real `swift build` there, and asserts exit 0 (compiler output is surfaced on failure).
  - **Golden** (parameterized over all three specs): generator output must equal the checked-in `*.generated.swift` byte-for-byte.
  - **Request shape**: builds actual `URLRequest`s from the generated enums and asserts URLs, methods, query items, headers, and JSON bodies — including the Supabase refresh flow (`POST …/token?grant_type=refresh_token` with the real refresh-token payload and `apikey` header).
  - **Unit**: name sanitization, type mapping, slash stripping, required/optional/array query params, operationId fallback, enum-name override, header-param TODOs, invalid-YAML errors.

## Notes & caveats

- Model generation covers the easy tier only — inline object properties, `oneOf`/`anyOf`, and recursion are out of scope and fall back to `String` via the tolerant type mapper (see TODO.md for the hard tail).
- Requires the sibling checkout `../declarative-requests-swift` (relative path dependency in `Package.swift`). The e2e test additionally references it by **absolute path** (`/Users/lazar/dev/declarative-requests-swift`), so the test suite is machine-local as-is.
- Toolchain: swift-tools-version 6.3, macOS 14+ (matching the DSL package). First build fetches Yams from the network.
- The initial implementation was hardened by an adversarial review pass that caught and fixed: ignored path-item-level `parameters` (literal `{petId}` left in URLs), unsanitized schema names, non-compiling `String([T])` for array params, empty-`switch` output for operation-less specs, and the `Error` schema shadowing `Swift.Error`.
