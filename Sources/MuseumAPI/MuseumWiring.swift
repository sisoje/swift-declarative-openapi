// Hand-written layer over Museum.generated.swift — minimal wiring: the spec
// declares one basic-auth scheme document-wide, so every operation is gated
// the same way, through the generated Security section.

import DeclarativeOpenAPIRuntime
import DeclarativeRequests
import Foundation

/// Session + environment in one place. Credentials are optional so the
/// client is constructible before any exist — a required-but-missing pair
/// fails the build at `request(_:)` with the generated scheme error.
struct MuseumClient {
    var baseURL: URL
    var credentials: (username: String, password: String)? = nil

    func request(_ operation: RedoclyMuseumAPI.Operation) throws -> URLRequest {
        try RedoclyMuseumAPI.authorized(operation, museumPlaceholderAuth: credentials)
            .base(baseURL)
            .request()
    }

    // Fully typed surface over this wiring: RedoclyMuseumAPI.Client field per
    // operation, defaults to the real transport.

    /// URLSession as the transport closure — this app's transport policy.
    private func urlSessionTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    /// Every operation decodes with a plain `JSONDecoder` — this app's decoding policy.
    private func plainDecoder(_: RedoclyMuseumAPI.Operation) -> JSONDecoder {
        JSONDecoder()
    }

    var api: RedoclyMuseumAPI.Client {
        .wired(
            execute: NetworkExecution(request: request, transport: urlSessionTransport, successStatuses: RedoclyMuseumAPI.Responses.successStatuses).execute,
            decoder: plainDecoder
        )
    }
}
