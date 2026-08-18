# swift-declarative-openapi

[![Build](https://github.com/sisoje/swift-declarative-openapi/actions/workflows/swift.yml/badge.svg)](https://github.com/sisoje/swift-declarative-openapi/actions/workflows/swift.yml)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fsisoje%2Fswift-declarative-openapi%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/sisoje/swift-declarative-openapi)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fsisoje%2Fswift-declarative-openapi%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/sisoje/swift-declarative-openapi)

Turns an OpenAPI document into a compile-checked **BackendSpec** for [swift-declarative-requests](https://github.com/sisoje/swift-declarative-requests): the whole backend as one closed Swift type with typed operations, models, and security gates. A small runtime ships alongside the generator to handle what a spec can't fully express (status-gated error handling, token refresh), so those stay as generated facts wired into shared mechanics rather than hand-rolled per app.

- 🚫 **Networking disappears from app code**: no `URLSession`, `URLRequest`, `JSONDecoder`, or status codes at the call site; the whole backend is one struct of typed closures ([Why](#why))
- 🧱 **Requests are declared, not assembled**: each operation *is* a request block, built by a result builder ([Requests](#requests-are-declared-not-assembled))
- 🔌 **Simple backend wiring**: base URL, transport, decoder. That's it ([Wiring](#wiring))
- 🔄 **Auth and refresh are per operation**: public calls never carry a token, never refresh one — Apple's generator drops security schemes and tells you to inject headers into *every* request ([Refresh](#refresh-knows-which-calls-need-it))
- 🧵 **The main actor stays free**: URL composition, body encoding, and JSON decoding run off the caller by `@concurrent` contract — the call site declares what it wants, never where it runs ([Main](#the-main-actor-stays-free))
- ✍️ **Even HMAC signing is one more composable block**: Binance's signing slots filled by the wiring, dead values at call sites ([HMAC](#hmac-signing-as-a-dsl-block))

## Why

**To erase networking from app code.** The endgame client is pure data, a struct of typed closures:

```swift
let pet = try await api.showPetById("42")   // petId in, Pet out. That is the whole API.
```

No `URLSession`. No `URLRequest`. No `JSONDecoder`. No status codes, no headers, no protocols. The client needs none of it. Those concepts are real, but each one lives in exactly one layer below, and never leaks up:

| networking concept | its only home |
|---|---|
| `URLSession` | the app's transport closure (`(URLRequest) async throws -> (Data, URLResponse)`) |
| `URLRequest` composition | the DSL blocks + the `NetworkExecution` seam |
| status codes | the generated `successStatuses` table + `ResponseError.evaluate` |
| `JSONDecoder` | the `ClientBuilder` decode step |
| tokens, refresh, auth headers | the wiring + `RefreshingExecutor` |

Expand that one line and it is always the same chain, input to model. Every step is mechanical, every step derivable from the spec, so not one of them is a decision app code should be making per call:

```swift
// input → operation → request → transport → evaluate → decode, each step separable
let petId = "42"
let operation = SwaggerPetstore.Operation.showPetById(petId: petId)
let request = try client.request(operation)
let response = try await session.data(for: request)
let data = try ResponseError.evaluate(response, successStatuses: SwaggerPetstore.Responses.successStatuses(operation))
let pet = try JSONDecoder().decode(Pet.self, from: data)
```

Generating every step is what collapses that chain back down to the one line — the whole petstore backend, three fields:

```swift
struct Client {
    var listPets: (_ limit: Int?) async throws -> Pets
    var createPets: (_ body: Pet) async throws -> Void       // 204 → Void
    var showPetById: (_ petId: String) async throws -> Pet
}
```

Output types are read from `responses:`, so the ladder above is what each field *is*. And because it is a plain struct of closures, a whole backend is a value you write by hand — no network in sight:

```swift
var api = Client.unimplemented                          // every field traps, by name
api.showPetById = { Pet(id: 1, name: "Rex", tag: $0) }  // state only what you need
```

That is the mocking story too — **no protocols, just field assignment** — and `api.showPetById("42")` from the top now answers from your closure. Swap the value for `Client.wired(execute:decoder:)` when it should reach a real server and not one call site changes; **wrap the `(Operation) → Data` seam it wires over and you have middleware**. Traps can't reach production, because `wired` fills every field.

The generator and runtime exist to manufacture that pure client from the spec, nothing more:

```sh
swift run declarative-openapi petstore.yaml
```

### Requests are declared, not assembled

Each operation *is* a request block: a `switch` over the enum whose branches list the request's parts — method, path, query, body — with no `URLRequest` mutated and no strings concatenated. An optional query item is an `if let`, a path parameter is interpolation, a JSON body is one line, and the compiler checks all of it — every line below generated from `paths:`:

```swift
enum SwaggerPetstore {
    enum Operation: RequestBuildable {
        case listPets(limit: Int?)
        case createPets(body: Pet)
        case showPetById(petId: String)

        var body: some RequestBuildable {
            switch self {
            case let .listPets(limit):
                Method.GET
                Endpoint("pets")
                if let limit {
                    Query("limit", String(limit))
                }
            case let .createPets(body):
                Method.POST
                Endpoint("pets")
                RequestBody.json(body)
            case let .showPetById(petId):
                Method.GET
                Endpoint("pets/\(petId)")
            }
        }
    }
}
```

### Wiring

Consuming it is a small hand-written wiring stating environment and policy, essentially petstore's entire hand-written layer:

```swift
struct PetstoreClient {
    var baseURL: URL

    var execution: NetworkExecution<SwaggerPetstore.Operation> {
        NetworkExecution(
            request: { try $0.base(baseURL).request() },                // this app's environment
            transport: { try await URLSession.shared.data(for: $0) },   // this app's transport policy
            successStatuses: SwaggerPetstore.Responses.successStatuses  // generated fact table
        )
    }

    var api: SwaggerPetstore.Client {
        .wired(execute: execution.execute) { _ in JSONDecoder() }
    }
}
```

Each operation is itself a `RequestBuildable` block, so the bare chain works too: `try SwaggerPetstore.Operation.showPetById(petId: "42").base(url).request()`.

### The typed Client

The top of the ladder is the generated **Client**: the backend as one struct of typed closures, output types read from `responses:` (`204` → `Void`, `image/png` → `Data`, `text/*` → UTF-8 `String`, json `$ref` → the model). Field names carry the operation; wrong pairings are unrepresentable; any field swaps for a stub (the mock up top). Its three fields are [up top](#why).

`Client.wired(execute:decoder:)` fills them from a single `(Operation) async throws -> Data` seam — a generated fact table over the runtime's four builder helpers (`endpoint`/`fire`/`raw`/`text`), one per response kind — with no parameter defaults and no opinion about realness: build the seam with `NetworkExecution(request:transport:successStatuses:)`, wrap it in middleware or replace it with a stub, and the fields can't tell the difference. The wiring hands the finished value over as `PetstoreClient(baseURL: url).api`.

## The main actor stays free

**Every CPU step of the wire runs off the caller — by contract, not by scheduler luck.** The caller is usually the main actor, and it stays completely relaxed: it constructs an enum case, suspends, and receives a decoded model. Everything between — walking the DSL blocks, composing the URL, `JSONEncoder` on the body, the transport, the status gate, `JSONDecoder` on the payload — happens on the concurrent pool:

```
MainActor                        concurrent pool
─────────                        ───────────────
try await api.showPetById("42")
    suspends ──────────────────► build URLRequest   (DSL blocks, JSON body encoding)
                                 transport          (URLSession)
                                 status gate        (ResponseError.evaluate)
                                 decode             (JSONDecoder)
    Pet ◄──────────────────────  done
```

Most async code gets this off-main behavior by accident of the current language default (SE-0338) — and silently loses it the day a module adopts `NonisolatedNonsendingByDefault`, when plain async closures start inheriting the caller's isolation and a multi-megabyte decode lands on the UI thread mid-scroll. Here both directions carry the guarantee in their declarations (`@concurrent`, SE-0461): `NetworkExecution.execute` owns the outbound half, the `ClientBuilder` decode step owns the inbound half, and the pairing is deliberate — the refresh gate goes the opposite way: it hops to the actor the executor was *constructed* on (`#isolation` captured at init, the same trick `Task {}` and SwiftUI's `Binding(get:set:)` use), because *its* correctness needs the actor that hosts the token bindings. Leave the caller where CPU work lives, come home where state lives.

Tests pin both halves from a `@MainActor` caller: the request closure and the decoder factory each execute inside their step and assert they are off the main thread.

Every spec also gets a **Responses section**: a pure fact table of the operation's spec-declared statuses (`deleteSpecialEvent` expects 204, `createPets` 201, …). The runtime's `ResponseError.evaluate` is the evaluate step of the chain up top: it gates transport results through that table and throws one lossless error; the layer that cares decodes the spec's typed error model from `error.data`:

```swift
struct ResponseError: Error {
    let data: Data
    let response: URLResponse
    var status: Int? { computed from response }
}
```

## Security

Petstore declares no `security:`, so nothing above mentioned it — absence mirrors absence. Specs that do declare it get a **Security section**: one gate and one attachment factory per scheme, both generated from `components.securitySchemes`.

### Refresh knows which calls need it

Token refresh is the same seam wrapped once more: the runtime's `RefreshingExecutor` turns 401 into a single-flight refresh and one retry, and the wiring only states how to mint a new token. The generated gates decide which operations ride it:

```swift
let refreshing = RefreshingExecutor(
    refreshTask: $refreshTask,            // non-nil while a refresh is in flight — concurrent 401s join it
    accessToken: $accessToken,
    executeOnce: execution.execute,       // the plain (Operation) → Data seam
    makeRefreshTask: { Task { await refresh() } },   // refresh() is non-throwing: it stores fresh tokens on success, keeps the old on transient failure
    isUnauthorized: { $0.status == 401 },
    needsAuth: Security.needsUserAuth     // generated gate: public operations bypass refresh entirely
)
let data = try await refreshing.executeWithRefresh(operation)
```

That `needsAuth` gate is the whole difference, and it is not something a lower layer can do — it needs a fact that only the spec has:

| where auth usually lives | what it can know | result |
|---|---|---|
| a middleware injecting headers | that a request is going out | every call carries the token, public endpoints included |
| a blanket 401 interceptor | that *some* request got a 401 | every call pays the refresh machinery; a stray 401 stampedes the refresh endpoint |
| generated `Security.needsUserAuth` | which operations the document declares `security:` for | public calls never join a refresh, never retry, never read the token |

The first row is not a straw man — it is the state of the art. Apple's own [swift-openapi-generator](https://github.com/apple/swift-openapi-generator) does not generate security schemes at all: [issue #37, "Support for security scheme/auth"](https://github.com/apple/swift-openapi-generator/issues/37), has been open since May 2023 and sits on the Post-1.0 milestone, and the documented workaround is custom middleware that *"injects appropriate headers to every outgoing request."* Every outgoing request — the generator has read your `security:` declarations and thrown them away, so the middleware has no way to tell `/signup` from `/user`.

That is the whole difference here. `security:` is a fact in the document, so it becomes a generated table rather than a discarded one: `Security.needsUserAuth(operation)` answers per operation, `authorized(_:apiKeyAuth:userAuth:)` demands exactly the credentials that operation requires and fails the build when one is missing, and the refresh gate reads the same table. A test pins the bypass.

The gate is also pinned to *where the tokens live*: the executor captures `#isolation` at construction and runs the gate there, so an executor built on the main actor keeps its single-flight check and every binding access on main **no matter which thread fires the call** — a background `Task` calling through the typed client still refreshes on main. This matters because SwiftUI bindings enforce their construction actor at runtime (a main-built binding traps when touched off-main); a witness test drives the full 401 → refresh → retry path from a detached task and asserts every token touch lands on main.

## Usage

```sh
swift run declarative-openapi Specs/petstore.yaml                 # generated Swift on stdout
swift run declarative-openapi Specs/petstore.yaml -o Petstore.swift
swift run declarative-openapi Specs/supabase-auth.yaml --exclude-scheme AdminAuth
```

Flags: `-o`/`--output <file>`, `--enum-name <Name>` (overrides the namespace name derived from `info.title`), `--exclude-scheme <Scheme>` (repeatable, drops every operation whose security requires that scheme, e.g. a server-only admin scheme, keeping the output client-only; recorded in the header comment), `-h`/`--help`. Missing/unreadable input or invalid YAML produces a clear error on stderr and exit code 1.

## Reference specs

Four reference specs are checked in: canonical upstream files (binance scoped to a subset, noted below), each with its generated output compiled on every build:

- `Specs/petstore.yaml`: the classic [petstore](https://learn.openapis.org/examples/v3.0/petstore.html) example (OpenAPI 3.0). `PetstoreWiring.swift` is the degenerate client: no security in the spec, so the client carries only the base URL.
- `Specs/museum.yaml`: the [Redocly Museum API](https://github.com/Redocly/museum-openapi-example) (OpenAPI 3.1): `$ref` parameters, scalar/enum component schemas, `allOf`, nested paths, and a `webhooks` section (webhooks aren't client-callable endpoints, so they're ignored). `MuseumWiring.swift` is the minimal client: document-wide basic auth, gated once through the generated `Security.museumPlaceholderAuth(username:password:)` factory.
- `Specs/supabase-auth.yaml`: the [Supabase Auth REST API](https://github.com/supabase/auth) (OpenAPI 3.0.3, ~60 operations): no-`operationId` fallback naming, templated server URLs, and three security schemes. Generated **client-only** (`--exclude-scheme AdminAuth`). `SupabaseAuthWiring.swift` shows the hand-written layer: `SupabaseAuthClient(baseURL:apikey:accessToken:)` wires session + environment once; `request(_ operation:)` composes one flat `RequestBlock` gated on the generated `Security` section, and `RefreshingExecutor` wraps the seam for 401 → single-flight refresh → one retry.
- `Specs/binance.yaml`: the official [binance/binance-api-swagger](https://github.com/binance/binance-api-swagger) spot API, scoped to the Market + Wallet tags (49 of ~340 operations, transitively `$ref`-complete, every kept definition byte-identical to upstream). It exists for HMAC request signing: the slot-filling `HMACSignature` block shown below lives in `BinanceWiring.swift`, with its own test suite (`BinanceSigningTests`). The API-key header, a real `securityScheme`, rides the generated `Security` gates like every other spec.

### Generation rules

- The output is one namespace enum (from `info.title`) whose sections mirror the OpenAPI document: schemas, `Operation` (a `RequestBuildable` enum, each operation IS a block), `Security`, and the server URL. One `Operation` case per operation, named from `operationId` (camelCase-sanitized); falls back to method + path (e.g. `getPetsPetId`) when `operationId` is missing.
- Path params are interpolated into `Endpoint(...)`; leading `/` is stripped because `Endpoint` paths are joined onto the base URL by `.base(url)`. Path-item-level `parameters` are merged into each operation (operation-level entries win by `(name, in)`).
- Query params: required → `Query("name", value)`; optional → wrapped in `if let`; non-`String` types stringified via `String(...)`; array-typed params emit a `for` loop of repeated `Query` blocks (the DSL's `buildArray`).
- `requestBody` (application/json): `$ref` → associated value of that model type + `RequestBody.json(body)`; inline schemas get a generated `<OperationId>Body` model with real properties.
- Parameters written as `$ref: "#/components/parameters/X"` are resolved to their component definitions (unresolvable refs are dropped).
- `security:` declarations generate the `Security` section (operation-level overrides the document default; `security: []` marks an operation public; OR-alternatives are flattened): `Security.schemes(_ operation:) -> Set<String>`, one `Security.needs<Scheme>(_ operation:)` gate per scheme, and one **attachment factory** per scheme derived from `components.securitySchemes`: `http bearer` → `Security.userAuth(token:)` wrapping `Authorization.bearer`, `apiKey in: header` → `Security.apiKeyAuth(_:)` wrapping `Header.custom(name)`, `http basic` → `Authorization.basic`. Omitted entirely when the spec declares no security. The composition itself is also generated, as the `Authorized` section: `static func authorized(_ operation:apiKeyAuth:userAuth:)` takes one optional per used scheme (parameter types derived from the scheme definitions: bearer → `String`, basic → `(username:password:)` tuple, apiKey → `String`) and returns the operation + gated credentials as one block, throwing the generated per-scheme error (`MissingAPIKeyAuth`, `MissingUserAuth`) at materialization when a required credential is nil. Environment comes last, per the DSL contract: the wiring binds stored credentials and applies `.base(baseURL).request()`. The checked-in Supabase target is **client-only**: generated with `--exclude-scheme AdminAuth`, so server-side operations (user management, SSO provider management, those needing the service-role JWT) are not generated at all.
- `components.schemas`: `object` (or `allOf`, flattened) → `struct X: Codable` with real properties, `array` → `typealias X = [Element]`, scalars → `typealias X = String/Int/Double/Bool` (`format: binary` → `Data`), string enums → `enum X: String, Codable`. Names are sanitized to valid Swift identifiers (`thing-request` → `ThingRequest`); names that would shadow stdlib types are prefixed (`Error` → `APIError`, `Date` → `APIDate`). The rename carries no semantics: `APIError` does **not** conform to `Swift.Error`, because OpenAPI has no way to mark a schema as an error model and we don't infer that from names. Apps that want to throw it add `extension APIError: Swift.Error {}` in hand-written code.
- Type mapping: `string`→`String`, `integer`→`Int`, `number`→`Double`, `boolean`→`Bool`, `array`→`[Element]`, `$ref`→model type. String schemas/parameters/properties with `enum:` values generate `enum X: String, Codable` (schemas at top level, parameters nested in the endpoint enum (`grant_type` → `GrantType`, used via `.rawValue`), and object properties nested in their struct, e.g. `PostTokenBody.Provider`); digit-leading values get a `_` prefix (`_1080p`); a parameter name reused with a different value set falls back to `String`.
- `servers[0].url` becomes `static let defaultBaseURL`. Header/cookie params are not generated (a `// TODO:` comment is emitted in the case instead). Specs with zero operations still produce compiling output (placeholder body instead of an illegal empty `switch`).
- Output is deterministic (schemas alphabetical, paths sorted, fixed method order) so it's golden-testable.

## HMAC signing as a DSL block

Some credentials can't be values. Binance's `signature` is an HMAC digest of the final query string and its `timestamp` is the send instant. OpenAPI can't model that as a securityScheme, so the spec declares both as required query parameters. Read those as **slots**: their values are unknowable at the call site, so the wiring (which owns the clock and the key) fills them with a DSL block composed after the operation like any other:

```swift
struct HMACSignature: RequestBuildable {
    let secretKey: String?
    let now: () -> Date

    var body: some RequestBuildable {
        RequestBlock { state in
            guard state.queryItems.contains(where: { $0.name == "signature" }) else { return }
            guard let secretKey else { throw MissingSecretKey() }

            let stamped = state.queryItems.map {
                $0.name == "timestamp" ? .init(name: "timestamp", value: nowInMillis) : $0   // now(), epoch ms
            }
            state.queryItems = stamped + [.init(name: "signature", value: hexDigest)]   // HMAC-SHA256 of stamped's encoded query, keyed by secretKey
        }
    }
}
```

`RequestBlock { state in … }` is the DSL's own state-reading primitive, so signing is one more composable block in the chain. No slot → untouched, slot without a key → the build fails like any credential gate:

```swift
try RequestBlock {
    BinanceSpotAPI.authorized(operation, apiKeyAuth: apiKey)
    HMACSignature(secretKey: secretKey, now: now)
}
.base(baseURL)
.request()
```

Call sites pass placeholders and never think about signing again; a test proves the slot values are dead:

```swift
let account = try await binance.api.getSapiV1AccountInfo(nil, 0, "")   // timestamp/signature: dead values, the wiring owns them
```

## Design conclusions

Settled over the project's evolution, enforced across every generated file:

1. **The authority ladder.** The spec decides everything it states: shapes, statuses, schemes, attachment mechanics, and all of it is generated. The wiring decides bindings and policy: credentials, transport, decoder, and all of it is hand-written. The caller materializes. Nothing lives below its authority: `URLSession`/`JSONDecoder` never appear in generated code, and spec knowledge is never hand-maintained.
2. **Sections mirror the document; absence mirrors absence.** No `security:` → no Security section, no `authorized` builder. No text responses → no `text` helper. What the spec doesn't say, the output doesn't contain.
3. **No parameter defaults on the seams.** `wired` and `authorized` demand every dependency explicitly; standard bindings are named options the caller passes, never silent choices. Nil is never the spelling for "not needed" — absence of the block is.
4. **One lossless error per boundary; store each fact once.** `ResponseError` carries data + raw response; `status` is a projection, not a field. The next layer decodes the spec's error model from `data` only when it wants it.
5. **Facts as tables, mechanics once.** `wired` is a one-line-per-operation fact table over the runtime's pack-generic `ClientBuilder`; `schemes(_:)` is a grouped switch. Cleverness is quarantined in mechanics; generated facts stay boring.
6. **The operation→type problem is solved at generation time**, in a table, never with phantoms, `Any`, or mirrored payload enums. Closures take the case's payload and construct the case inside, making wrong pairings unrepresentable.
7. **Every ladder rung stays public.** The typed Client is sugar, not a gate: `request`/`authorized`/`evaluate`/raw `Data` all remain directly usable, decode-later end to end.
8. **Base comes last.** Spec composes (`authorized` returns a block), wiring situates (`.base(url)`), caller materializes (`.request()`).
9. **The client is pure data; networking concepts never leak up.** A struct of typed closures is the entire app-facing surface; `URLSession`/`URLRequest`/`JSONDecoder`/status codes each live in exactly one lower layer. Runtime types follow one shape: dependencies as stored closures, behavior as the output function.
10. **Universal mechanics live once, in the runtime; generated files carry facts only.** Every generated one-liner was audited by one test — *does deleting it create a place where hand-written code could contradict the spec and still compile?* — and none survived: inject the generated fact (`successStatuses`, `schemes`) into runtime mechanics (`NetworkExecution`, `ResponseError.evaluate`, `ClientBuilder`) rather than generating pre-composed conveniences.
11. **Names describe mechanics, not claims** (`wired`, not `live` or `real`; realness is decided by the closures passed), and sugar that duplicates an existing spelling gets deleted.

## Package layout

- `Sources/DeclarativeOpenAPI`: all parsing (via [Yams](https://github.com/jpsim/Yams)) and codegen; `SpecGenerator(enumNameOverride:).generate(yaml:) -> String`.
- `Sources/DeclarativeOpenAPIRuntime`: the small shared runtime generated code imports, four witness structs (dependencies as properties, behavior as the output function): the universal non-generic `ResponseError` with its `evaluate` gate (typed throws), `NetworkExecution<Operation>` (the `(Operation) → Data` seam: request → transport → gate over the injected `successStatuses` table), `ClientBuilder<Operation>` (the pack-generic typed-closure mechanics `wired` tables build over), and `RefreshingExecutor<Operation>` (401 → single-flight refresh → one retry), ready to slap onto any backend's seam.
- `Sources/DeclarativeOpenAPICLI`: the `swift-declarative-openapi` executable (plain `CommandLine.arguments`, no argument-parser dependency).
- `Sources/PetstoreAPI`, `Sources/MuseumAPI`, `Sources/SupabaseAuthAPI`, and `Sources/BinanceAPI`: the **checked-in generated outputs** (plus each backend's hand-written wiring), compiled against DeclarativeRequests on every `swift build`, so compilability of generated code is proven by the build itself.
- `Specs/`: the canonical spec files.
- `Tests/DeclarativeOpenAPITests`, 82 tests:
  - **Golden** (parameterized over all four specs): generator output must equal the checked-in `*.generated.swift` byte-for-byte. Those files are the sources of the four `<Name>API` targets, so every `swift build` compiles them against the real DeclarativeRequests dependency — golden equality plus a green build is the end-to-end proof that generator output compiles against the DSL, no temp-package harness needed.
  - **Request shape**: builds actual `URLRequest`s from the generated enums and asserts URLs, methods, query items, headers, and JSON bodies, including the Supabase refresh flow (`POST …/token?grant_type=refresh_token` with the real refresh-token payload and `apikey` header).
  - **Unit**: name sanitization, type mapping, slash stripping, required/optional/array query params, operationId fallback, enum-name override, header-param TODOs, invalid-YAML errors.

## Notes & caveats

- Model generation covers the easy tier only: inline object properties, `oneOf`/`anyOf`, and recursion are out of scope and fall back to `String` via the tolerant type mapper (see TODO.md for the hard tail).
- Declaring an error-model schema is bad API practice. One shape rarely fits every failure. The generator stays neutral: `ResponseError` is lossless, so callers who want the spec's error model decode it from `error.data`, and everyone else loses nothing.
- Depends on published [swift-declarative-requests](https://github.com/sisoje/swift-declarative-requests) tags (`from: "2.0.0"`), not on a sibling checkout — clone and build anywhere.
- Toolchain: swift-tools-version 6.3, macOS 14+ (matching the DSL package). First build fetches Yams and DeclarativeRequests from the network.
- The initial implementation was hardened by an adversarial review pass that caught and fixed: ignored path-item-level `parameters` (literal `{petId}` left in URLs), unsanitized schema names, non-compiling `String([T])` for array params, empty-`switch` output for operation-less specs, and the `Error` schema shadowing `Swift.Error`.
