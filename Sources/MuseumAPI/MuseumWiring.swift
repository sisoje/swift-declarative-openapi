// Hand-written layer over Museum.generated.swift — minimal wiring: the spec
// declares one basic-auth scheme document-wide, so every operation is gated
// the same way, through the generated Security section.

import DeclarativeOpenAPIRuntime
import DeclarativeRequests
import Foundation

/// Session + environment in one place. Credentials are optional so the
/// client is constructible before any exist — a required-but-missing pair
/// fails the build at `request(_:)` with the generated scheme error.
struct MuseumClient: Sendable {
    var baseURL: URL
    var credentials: (username: String, password: String)? = nil

    func request(_ operation: RedoclyMuseumAPI.Operation) throws -> URLRequest {
        try RedoclyMuseumAPI.authorized(operation, museumPlaceholderAuth: credentials)
            .base(baseURL)
            .request()
    }

    /// The (Operation) → Data seam: this app's request building and transport,
    /// gated by the generated status table.
    var execution: NetworkExecution<RedoclyMuseumAPI.Operation> {
        NetworkExecution(
            request: request,
            transport: { try await URLSession.shared.data(for: $0) },
            successStatuses: RedoclyMuseumAPI.Responses.successStatuses
        )
    }

    var api: RedoclyMuseumAPI.Client {
        .wired(execute: execution.execute) { _ in JSONDecoder() }
    }
}
