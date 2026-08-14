// Hand-written layer over SupabaseAuth.generated.swift — the generated enum
// carries the endpoint shapes; this file wires Supabase auth headers and the
// token-refresh flow on top.

import DeclarativeRequests
import Foundation

struct MissingAPIKey: Error {}
struct MissingAccessToken: Error {}
struct MissingRefreshToken: Error {}

extension RequestBuildable {
    /// Every Supabase Auth request carries the project `apikey` header, so a
    /// missing key is a configuration error: it fails the build at `.request()`.
    /// For the spec's few keyless endpoints, don't chain `.keyed` — omission
    /// is spelled by not declaring the block.
    func keyed(apikey: String?) -> some RequestBuildable {
        RequestBlock {
            self
            if let apikey {
                Header.custom("apikey").setValue(apikey)
            } else {
                RequestFailure(MissingAPIKey())
            }
        }
    }

    /// Attaches the user bearer where `needsAuth` says the spec requires it
    /// (pass the generated `needsUserAuth`); a required-but-nil token fails
    /// the build at `.request()`.
    func authorized(accessToken: String?, needsAuth: Bool) -> some RequestBuildable {
        RequestBlock {
            self
            if needsAuth {
                if let accessToken {
                    Authorization.bearer(accessToken)
                } else {
                    RequestFailure(MissingAccessToken())
                }
            }
        }
    }
}

extension SupabaseAuthRESTAPIEndpoint {
    /// `POST /token?grant_type=refresh_token` with the generated body model.
    ///
    /// The refresh token is this endpoint's body parameter; it is optional
    /// only because the stored token may not exist on this device yet — the
    /// builder is always constructible, and nil fails the build at `.request()`.
    static func refreshSession(refreshToken: String?) -> some RequestBuildable {
        RequestBlock {
            if let refreshToken {
                SupabaseAuthRESTAPIEndpoint.postToken(
                    grantType: .refreshToken,
                    body: PostTokenBody(refreshToken: refreshToken)
                )
            } else {
                RequestFailure(MissingRefreshToken())
            }
        }
    }
}
