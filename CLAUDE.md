# Working conventions for this repo

- **Docs flow**: substantive notes, explanations, and caveats produced while working are persisted into `README.md` here — not left in chat. Improvement suggestions for the DSL package go into `../declarative-requests-swift/TODO.md`, not into its sources; never modify that package's code unless explicitly asked. Once a suggestion is addressed, its TODO entry is removed (no addressed-item records) — residual contract notes become small doc comments in that package's code or one-line README additions, left uncommitted for review.
- **Dependency**: `../declarative-requests-swift` (sibling checkout) is the DeclarativeRequests DSL this generator targets. Read its sources for DSL semantics before changing codegen.
- **Golden sync**: whenever codegen output changes, regenerate `Sources/PetstoreAPI/Petstore.generated.swift` by running the generator on `Specs/petstore.yaml` — the golden test compares byte-for-byte.
- **Spec file**: `Specs/petstore.yaml` is the byte-exact canonical petstore file from the OAI repository; don't reformat it.
- **Verification**: `swift build && swift test` must be green before declaring anything done. The e2e test proves generated code compiles against the DSL via a real `swift build` in a temp package.
- **Git**: commit locally on `main`; no remote, no push.
