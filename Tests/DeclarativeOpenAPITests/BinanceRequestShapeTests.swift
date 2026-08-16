@testable import BinanceAPI
import DeclarativeRequests
import Foundation
import Testing

private let client = BinanceClient(
    baseURL: URL(string: "https://api.binance.com")!,
    apiKey: "my-api-key",
    secretKey: nil,
    now: Date.init
)

@Test func publicOperationCarriesNoCredentialsAtAll() throws {
    // Even with an API key configured, a public operation gets neither the
    // header (generated Security gate) nor signing slots (none declared).
    let request = try client.request(.getApiV3Ping)
    #expect(request.url?.absoluteString == "https://api.binance.com/api/v3/ping")
    #expect(request.value(forHTTPHeaderField: "X-MBX-APIKEY") == nil)
}

@Test func securityGatesComeFromTheSpec() {
    #expect(BinanceSpotAPI.Security.needsApiKeyAuth(.getApiV3Ping) == false)
    #expect(BinanceSpotAPI.Security.needsApiKeyAuth(
        .getSapiV1AccountInfo(recvWindow: nil, timestamp: 0, signature: "")) == true)
}
