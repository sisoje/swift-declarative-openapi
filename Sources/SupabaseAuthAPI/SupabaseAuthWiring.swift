// Hand-written layer over SupabaseAuth.generated.swift — the generated
// namespace carries the spec sections (Operation, Security); this client
// wires session + environment in one place, per the DSL's BackendSpec
// layering.

import DeclarativeRequests
import Foundation

struct MissingAPIKey: Error {}
struct MissingAccessToken: Error {}
struct MissingRefreshToken: Error {}

extension SupabaseAuthRESTAPI.Operation {
    /// `POST /token?grant_type=refresh_token` with the generated body model —
    /// a named constructor for the one `postToken` shape a client refreshes with.
    static func refreshSession(refreshToken: String) -> Self {
        .postToken(grantType: .refreshToken, body: .init(refreshToken: refreshToken))
    }
}

/// Session + environment in one place; gating on the generated Security
/// section is its rule. Credentials are optional so the client is
/// constructible before any session exists — a required-but-missing one
/// fails the build at `request(_:)`.
struct SupabaseAuthClient {
    var baseURL: URL
    var apikey: String?
    var accessToken: String?

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

    /// `POST /token?grant_type=refresh_token` — the refresh token is the
    /// operation's body parameter; optional because no stored token may
    /// exist on this device yet.
    func refreshSessionRequest(refreshToken: String?) throws -> URLRequest {
        guard let refreshToken else { throw MissingRefreshToken() }
        return try request(.refreshSession(refreshToken: refreshToken))
    }
}
