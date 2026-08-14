// Hand-written layer over SupabaseAuth.generated.swift — the generated enum
// carries the endpoint shapes; this file wires Supabase auth headers and the
// token-refresh flow on top.

import DeclarativeRequests
import Foundation

extension RequestBuildable {
    /// Every Supabase Auth request carries the project `apikey` header;
    /// `nil` omits it (only sensible for the spec's few public endpoints).
    func keyed(apikey: String?) -> some RequestBuildable {
        RequestBlock {
            self
            if let apikey {
                Header.custom("apikey").setValue(apikey)
            }
        }
    }

}

extension SupabaseAuthRESTAPIEndpoint {
    struct MissingAccessToken: Error {}

    /// Applies the user bearer only where the spec requires `UserAuth`
    /// (per the generated flag); a required-but-missing token fails the
    /// build with the spec's own error — the README's Open Spec rule that
    /// a half-authorized request can never reach the wire.
    func authorized(accessToken: String?) -> some RequestBuildable {
        RequestBlock {
            self
            if needsUserAuth {
                if let accessToken {
                    Authorization.bearer(accessToken)
                } else {
                    RequestBlock { _ in throw MissingAccessToken() }
                }
            }
        }
    }

    /// `POST /token?grant_type=refresh_token` — rides the generated case for
    /// method, path, and query, and lays the real payload over the stub body:
    /// blocks apply in order, so the later `RequestBody.json` wins.
    static func refreshSession(refreshToken: String) -> some RequestBuildable {
        RequestBlock {
            SupabaseAuthRESTAPIEndpoint.postToken(grantType: "refresh_token", body: PostTokenBody())
            RequestBody.json(["refresh_token": refreshToken])
        }
    }
}
