// Hand-written layer over SupabaseAuth.generated.swift — the generated enum
// carries the endpoint shapes; this file wires Supabase auth headers and the
// token-refresh flow on top.

import DeclarativeRequests
import Foundation

struct MissingAPIKey: Error {}

extension RequestBuildable {
    /// Every Supabase Auth request carries the project `apikey` header, so a
    /// missing key is a configuration error: it fails the build at `.request`.
    /// For the spec's few keyless endpoints, don't chain `.keyed` — omission
    /// is spelled by not declaring the block.
    func keyed(apikey: String?) -> some RequestBuildable {
        RequestBlock {
            self
            if let apikey {
                Header.custom("apikey").setValue(apikey)
            } else {
                RequestBlock { _ in throw MissingAPIKey() }
            }
        }
    }
}

extension SupabaseAuthRESTAPIEndpoint {
    struct MissingAccessToken: Error {}
    struct MissingRefreshToken: Error {}

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
    ///
    /// The builder itself never requires the token — there may be none stored
    /// on this device yet — but a nil token fails the build at `.request`.
    static func refreshSession(refreshToken: String?) -> some RequestBuildable {
        RequestBlock {
            SupabaseAuthRESTAPIEndpoint.postToken(grantType: "refresh_token", body: PostTokenBody())
            if let refreshToken {
                RequestBody.json(["refresh_token": refreshToken])
            } else {
                RequestBlock { _ in throw MissingRefreshToken() }
            }
        }
    }
}
