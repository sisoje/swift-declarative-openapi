// Hand-written layer over Binance.generated.swift.
//
// OpenAPI has no HMAC security type, so the spec models signing as two
// required query parameters on every private operation: `timestamp` and
// `signature`. Read them as declared *slots*, not caller inputs — their
// values are unknowable at the call site: the timestamp belongs to the
// clock at send time, and the signature is a digest of the wire bytes,
// which don't exist until the request is built. Both owners live here,
// so the wiring fills the slots: callers pass any placeholder
// (`timestamp: 0, signature: ""`) and the values are overwritten on the
// way out. The API-key header is an ordinary securityScheme and rides the
// generated Security gates like every other spec.

import CryptoKit
import DeclarativeOpenAPIRuntime
import DeclarativeRequests
import Foundation

struct MissingSecretKey: Error {}

/// Fills the spec's signing slots — a DSL block, composed after the blocks
/// that write the query: no `signature` slot → pass through untouched;
/// slot but no key → fail the build like every credential gate; otherwise
/// stamp `timestamp` from the clock, HMAC-SHA256 the accumulated query,
/// append the digest last.
struct HMACSignature: RequestBuildable {
    let secretKey: String?
    let now: @Sendable () -> Date

    var body: some RequestBuildable {
        RequestBlock { state in
            guard state.queryItems.contains(where: { $0.name == "signature" }) else { return }
            guard let secretKey else { throw MissingSecretKey() }

            let stamped = state.queryItems
                .filter { $0.name != "signature" }
                .map { $0.name == "timestamp" ? URLQueryItem(name: "timestamp", value: String(Int(now().timeIntervalSince1970 * 1000))) : $0 }

            var wire = URLComponents()
            wire.queryItems = stamped
            let digest = HMAC<SHA256>.authenticationCode(
                for: Data((wire.percentEncodedQuery ?? "").utf8),
                using: SymmetricKey(data: Data(secretKey.utf8))
            ).map { String(format: "%02x", $0) }.joined()

            state.queryItems = stamped + [URLQueryItem(name: "signature", value: digest)]
        }
    }
}

/// Environment + credentials + clock in one place. `apiKey` gates through
/// the generated Security section; `secretKey` is demanded lazily — only
/// when an operation actually carries a signature slot. The clock is
/// injected policy (`now: Date.init` in an app), so tests pin it.
struct BinanceClient: Sendable {
    let baseURL: URL
    let apiKey: String?
    let secretKey: String?
    let now: @Sendable () -> Date

    /// One request path for every operation: the signing block composes
    /// after the authorized operation like any other block.
    func request(_ operation: BinanceSpotAPI.Operation) throws -> URLRequest {
        try RequestBlock {
            BinanceSpotAPI.authorized(operation, apiKeyAuth: apiKey)
            HMACSignature(secretKey: secretKey, now: now)
        }
        .base(baseURL)
        .request()
    }

    /// Fully typed surface over the signing request path.
    /// The (Operation) → Data seam: this app's request building and transport,
    /// gated by the generated status table.
    var execution: NetworkExecution<BinanceSpotAPI.Operation> {
        NetworkExecution(
            request: request,
            transport: { try await URLSession.shared.data(for: $0) },
            successStatuses: BinanceSpotAPI.Responses.successStatuses
        )
    }

    var api: BinanceSpotAPI.Client {
        .wired(execute: execution.execute) { _ in JSONDecoder() }
    }
}
