// Hand-written layer over SupabaseAuth.generated.swift — the generated enum
// carries the endpoint shapes; this file wires Supabase auth headers and the
// token-refresh flow on top.

import DeclarativeRequests
import Foundation

extension RequestBuildable {
    /// Every Supabase Auth request carries the project `apikey` header.
    func keyed(apikey: String) -> some RequestBuildable {
        RequestBlock {
            self
            Header.custom("apikey").setValue(apikey)
        }
    }

    /// User-scoped endpoints additionally send the access token as a bearer.
    func authorized(accessToken: String) -> some RequestBuildable {
        RequestBlock {
            self
            Authorization.bearer(accessToken)
        }
    }
}

extension SupabaseAuthRESTAPIEndpoint {
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
