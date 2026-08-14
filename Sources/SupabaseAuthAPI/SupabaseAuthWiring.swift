// Hand-written layer over SupabaseAuth.generated.swift — the generated
// namespace carries the spec sections (Operation, Security); this client
// wires session + environment in one place, per the DSL's BackendSpec
// layering.

import DeclarativeOpenAPIRuntime
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
    @Binding var refreshToken: String?
    @Binding var refreshTask: Task<Void, Never>?

    func request(_ operation: SupabaseAuthRESTAPI.Operation) throws -> URLRequest {
        try SupabaseAuthRESTAPI.authorized(operation, apiKeyAuth: apikey, userAuth: accessToken)
            .base(baseURL)
            .request()
    }

    /// URLSession as the transport closure — this app's transport policy.
    private func urlSessionTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    /// Every operation decodes with a plain `JSONDecoder` — this app's decoding policy.
    private func plainDecoder(_: SupabaseAuthRESTAPI.Operation) -> JSONDecoder {
        JSONDecoder()
    }

    /// The (Operation) → Data seam without middleware.
    private var executeOnce: (SupabaseAuthRESTAPI.Operation) async throws -> Data {
        SupabaseAuthRESTAPI.Client.execution(request: request, transport: urlSessionTransport)
    }

    /// The refresh work as a Task — spends the stored refresh token through
    /// `apiOnce` (never the refreshed pipeline: no recursion) and writes both
    /// rotated tokens back. A definitive rejection nils the tokens — in
    /// reactive SwiftUI the nil binding IS the logout. Transient failure
    /// leaves tokens unchanged, so RefreshingExecutor throws the original error.
    private func makeRefreshTask() -> Task<Void, Never> {
        Task { @MainActor in
            do {
                let session = try await apiOnce.postToken(.refreshToken, .init(refreshToken: refreshToken))
                accessToken = session.accessToken
                refreshToken = session.refreshToken ?? refreshToken
            } catch {
                if let status = (error as? SupabaseAuthRESTAPI.ResponseError)?.status, (400 ..< 500).contains(status) {
                    // The server rejected the refresh token — session dead, log out.
                    accessToken = nil
                    refreshToken = nil
                }
                // Otherwise transient (network, redirects, 5xx): keep tokens; a later call may retry.
            }
        }
    }
    
    /// Fully typed surface over the bare seam — no middleware.
    var apiOnce: SupabaseAuthRESTAPI.Client {
        return .wired(execute: executeOnce, decoder: plainDecoder)
    }

    /// Fully typed surface: every field rides the refresh middleware —
    /// 401 → single-flight refresh → one retry.
    var api: SupabaseAuthRESTAPI.Client {
        let refreshed = RefreshingExecutor(
            refreshTask: $refreshTask,
            accessToken: $accessToken,
            executeOnce: executeOnce,
            refresh: makeRefreshTask,
            isError401: { ($0 as? SupabaseAuthRESTAPI.ResponseError)?.status == 401 },
            needsAuth: SupabaseAuthRESTAPI.Security.needsUserAuth
        )
        return .wired(execute: refreshed.executeRefreshed, decoder: plainDecoder)
    }
}
