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
struct SupabaseAuthClient: Sendable {
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

    /// The (Operation) → Data seam without middleware.
    var executeOnce: @Sendable (SupabaseAuthRESTAPI.Operation) async throws -> Data {
        NetworkExecution(request: request, transport: { try await URLSession.shared.data(for: $0) }, successStatuses: SupabaseAuthRESTAPI.Responses.successStatuses).execute
    }

    /// The refresh work as a Task — `refresh()` wrapped in the single-flight
    /// handle the executor joins on.
    func makeRefreshTask() -> Task<Void, Never> {
        Task { await refresh() }
    }

    /// Non-throwing by signature — no error can escape the refresh path.
    /// Spends the stored refresh token through `api` itself: postToken
    /// doesn't need user auth, so the executor's needsAuth guard routes it
    /// straight to the bare seam — no recursion, no self-join. Success
    /// writes both rotated tokens back. A definitive rejection nils the
    /// tokens — in reactive SwiftUI the nil binding IS the logout.
    /// Transient failure leaves tokens unchanged, so RefreshingExecutor
    /// throws the original error.
    @MainActor
    func refresh() async {
        do {
            let session = try await api.postToken(.refreshToken, .init(refreshToken: refreshToken))
            accessToken = session.accessToken
            refreshToken = session.refreshToken ?? refreshToken
        } catch {
            if let status = (error as? ResponseError)?.status, (400 ..< 500).contains(status) {
                // The server rejected the refresh token — session dead, log out.
                accessToken = nil
                refreshToken = nil
            }
            // Otherwise transient (network, redirects, 5xx): keep tokens; a later call may retry.
        }
    }
    
    /// Fully typed surface: every field rides the refresh middleware —
    /// 401 → single-flight refresh → one retry.
    var api: SupabaseAuthRESTAPI.Client {
        let refreshed = RefreshingExecutor(
            refreshTask: $refreshTask,
            accessToken: $accessToken,
            executeOnce: executeOnce,
            makeRefreshTask: makeRefreshTask,
            isUnauthorized: { $0.status == 401 },
            needsAuth: SupabaseAuthRESTAPI.Security.needsUserAuth
        )
        return .wired(execute: refreshed.executeWithRefresh) { _ in JSONDecoder() }
    }
}
