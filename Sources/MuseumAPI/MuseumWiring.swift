// Hand-written layer over Museum.generated.swift — minimal wiring: the spec
// declares one basic-auth scheme document-wide, so every operation is gated
// the same way, through the generated Security section.

import DeclarativeRequests
import Foundation


/// URLSession as the transport closure: `URLRequest` in, `(Data, URLResponse)` out.
func urlSessionTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
    try await URLSession.shared.data(for: request)
}

/// Every operation decodes with a plain `JSONDecoder` — swap this when one doesn't.
func plainDecoder(_ operation: RedoclyMuseumAPI.Operation) -> JSONDecoder {
    JSONDecoder()
}

struct MissingCredentials: Error {}

/// Session + environment in one place. Credentials are optional so the
/// client is constructible before any exist — a required-but-missing pair
/// fails the build at `request(_:)`.
struct MuseumClient {
    var baseURL: URL
    var username: String?
    var password: String?

    func request(_ operation: RedoclyMuseumAPI.Operation) throws -> URLRequest {
        try RequestBlock {
            operation
            BaseURL(baseURL)
            if RedoclyMuseumAPI.Security.needsMuseumPlaceholderAuth(operation) {
                if let username, let password {
                    RedoclyMuseumAPI.Security.museumPlaceholderAuth(username: username, password: password)
                } else {
                    RequestFailure(MissingCredentials())
                }
            }
        }.request()
    }

    /// Fully typed surface over this wiring: RedoclyMuseumAPI.Client field per
    /// operation, defaults to the real transport.
    var api: RedoclyMuseumAPI.Client {
        .wired(request: request, transport: urlSessionTransport, decoder: plainDecoder)
    }
}
