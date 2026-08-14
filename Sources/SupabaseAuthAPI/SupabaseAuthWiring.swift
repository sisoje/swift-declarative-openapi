// Hand-written layer over SupabaseAuth.generated.swift — the generated
// namespace carries the spec sections (Operation, Security); this client
// wires session + environment in one place, per the DSL's BackendSpec
// layering.

import DeclarativeRequests
import Foundation
import SwiftUI


/// URLSession as the transport closure: `URLRequest` in, `(Data, URLResponse)` out.
func urlSessionTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
    try await URLSession.shared.data(for: request)
}

/// Every operation decodes with a plain `JSONDecoder` — swap this when one doesn't.
func plainDecoder(_ operation: SupabaseAuthRESTAPI.Operation) -> JSONDecoder {
    JSONDecoder()
}

struct MissingAPIKey: Error {}
struct MissingAccessToken: Error {}

// we want client to be reactive

/// Session + environment in one place; gating on the generated Security
/// section is its rule. Credentials are optional so the client is
/// constructible before any session exists — a required-but-missing one
/// fails the build at `request(_:)`.
struct SupabaseAuthClient {
    let baseURL: URL
    @Binding var apikey: String?
    @Binding var accessToken: String?
    @Binding var refreshToken: String?

    func request(_ operation: SupabaseAuthRESTAPI.Operation) throws -> URLRequest {
        try RequestBlock {
            operation
            BaseURL(baseURL)
            if SupabaseAuthRESTAPI.Security.needsAPIKeyAuth(operation) {
                if let apikey {
                    SupabaseAuthRESTAPI.Security.apiKeyAuth(apikey)
                } else {
                    RequestFailure(MissingAPIKey())
                }
            }
            if SupabaseAuthRESTAPI.Security.needsUserAuth(operation) {
                if let accessToken {
                    SupabaseAuthRESTAPI.Security.userAuth(token: accessToken)
                } else {
                    RequestFailure(MissingAccessToken())
                }
            }
        }.request()
    }


    /// Fully typed surface over this wiring: SupabaseAuthRESTAPI.Client field per
    /// operation, defaults to the real transport.
    var api: SupabaseAuthRESTAPI.Client {
        .wired(request: request, transport: urlSessionTransport, decoder: plainDecoder)
    }
}
