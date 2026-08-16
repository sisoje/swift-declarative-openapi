@testable import BinanceAPI
import CryptoKit
import DeclarativeOpenAPIRuntime
import DeclarativeRequests
import Foundation
import Testing

/// The HMAC slot-filling story: the spec declares `timestamp`/`signature`
/// as required query parameters (OpenAPI has no HMAC scheme type), and the
/// wiring's `HMACSignature` block owns their values — the clock and the key
/// live there, so whatever the caller writes into the slots is dead.
@Suite struct BinanceSigningTests {
    // Pinned clock: 2023-11-14T22:13:20Z → Binance's millisecond epoch 1700000000000.
    let client = BinanceClient(
        baseURL: URL(string: "https://api.binance.com")!,
        apiKey: "my-api-key",
        secretKey: "my-secret-key",
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    @Test func fillsTheSpecSigningSlots() throws {
        let request = try client.request(
            .getSapiV1AccountInfo(recvWindow: 5000, timestamp: 0, signature: "")
        )
        #expect(request.value(forHTTPHeaderField: "X-MBX-APIKEY") == "my-api-key")

        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        #expect(items.contains { $0.name == "recvWindow" && $0.value == "5000" })
        #expect(items.contains { $0.name == "timestamp" && $0.value == "1700000000000" })
        #expect(items.last?.name == "signature")

        // The cryptographic proof: recompute the digest independently over
        // the final URL's wire bytes (everything before the appended
        // signature) and compare — this also pins that the block's pre-base
        // signing encodes identically to the post-base wire query.
        var unsigned = components
        unsigned.queryItems = items.dropLast()
        let expected = HMAC<SHA256>.authenticationCode(
            for: Data((unsigned.percentEncodedQuery ?? "").utf8),
            using: SymmetricKey(data: Data("my-secret-key".utf8))
        ).map { String(format: "%02x", $0) }.joined()
        #expect(items.last?.value == expected)
    }

    @Test func placeholderSlotValuesAreDeadValues() throws {
        // The design claim itself: whatever the caller writes into the slots
        // has no effect — the wiring owns both values.
        let a = try client.request(.getSapiV1AccountInfo(recvWindow: nil, timestamp: 0, signature: ""))
        let b = try client.request(.getSapiV1AccountInfo(recvWindow: nil, timestamp: 123_456, signature: "junk"))
        #expect(a.url == b.url)
    }

    @Test func signedOperationWithoutSecretKeyFailsAtRequest() {
        let keyless = BinanceClient(baseURL: client.baseURL, apiKey: "my-api-key", secretKey: nil, now: Date.init)
        #expect(throws: MissingSecretKey.self) {
            try keyless.request(.getSapiV1AccountInfo(recvWindow: nil, timestamp: 0, signature: ""))
        }
    }

    @Test func publicOperationNeedsNoSecretKey() throws {
        let keyless = BinanceClient(baseURL: client.baseURL, apiKey: nil, secretKey: nil, now: Date.init)
        let request = try keyless.request(.getApiV3Time)
        #expect(request.url?.absoluteString == "https://api.binance.com/api/v3/time")
    }

    @Test func typedClientRidesTheSigningSeam() async throws {
        // End to end: the pure-data client field fires a signed operation;
        // the stub transport sees the filled slots on the wire and answers;
        // the field hands back the decoded model. No networking concept at
        // the call site.
        let api = BinanceSpotAPI.Client.wired(
            execute: NetworkExecution(
                request: client.request,
                transport: { request in
                    let query = request.url?.query ?? ""
                    #expect(query.contains("timestamp=1700000000000"))
                    #expect(query.contains("signature="))
                    #expect(!query.contains("signature=&") && !query.hasSuffix("signature="))
                    return (Data(#"{"isFutureEnabled":true,"isMarginEnabled":false,"vipLevel":3}"#.utf8),
                            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                },
                successStatuses: BinanceSpotAPI.Responses.successStatuses
            ).execute,
            decoder: { _ in JSONDecoder() }
        )
        let account = try await api.getSapiV1AccountInfo(nil, 0, "")
        #expect(account.vipLevel == 3)
        #expect(account.isFutureEnabled == true)
    }
}
