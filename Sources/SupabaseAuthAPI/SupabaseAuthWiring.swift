// Hand-written layer over SupabaseAuth.generated.swift — the generated
// namespace carries the spec sections (Operation, Security); this client
// wires session + environment in one place, per the DSL's BackendSpec
// layering.

import DeclarativeRequests
import Foundation
import SwiftUI

// we want client to be reactive

/// Session + environment in one place; gating on the generated Security
/// section is its rule. Credentials are optional so the client is
/// constructible before any session exists — a required-but-missing one
/// fails the build at `request(_:)`.
struct SupabaseAuthClient {
    let baseURL: URL
    @Binding var apikey: String?
    @Binding var accessToken: String?

    func request(_ operation: SupabaseAuthRESTAPI.Operation) throws -> URLRequest {
        try SupabaseAuthRESTAPI.authorized(operation, apiKeyAuth: apikey, userAuth: accessToken)
            .base(baseURL)
            .request()
    }

    // Fully typed surface over this wiring: SupabaseAuthRESTAPI.Client field per
    // operation, defaults to the real transport.

    /// URLSession as the transport closure — this app's transport policy.
    private func urlSessionTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    /// Every operation decodes with a plain `JSONDecoder` — this app's decoding policy.
    private func plainDecoder(_: SupabaseAuthRESTAPI.Operation) -> JSONDecoder {
        JSONDecoder()
    }

    var api: SupabaseAuthRESTAPI.Client {
        .wired(request: request, transport: urlSessionTransport, decoder: plainDecoder)
    }
}
