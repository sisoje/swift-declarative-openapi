import SwiftUI

/// 401 → single-flight refresh → one retry, generic over any spec's Operation.
///
/// Strategy: try to refresh; if refresh isn't possible or didn't happen, throw
/// the original error. Single-flight holds by the nil-gate: `refreshTask` stays
/// non-nil from creation until its creator clears it, so a second refresh can
/// never start while one is in flight. `alreadyRefreshing` doubles as the
/// staleness barrier: a call that joined a refresh ran with the fresh token,
/// so its failure escalates instead of re-refreshing.
///
/// Deliberately minimal — no isolation annotations. Known caveat: as a
/// nonisolated async function, `executeRefreshed` hops off the caller's
/// actor (SE-0338), so the nil-gate is not actor-atomic today. Revisit when
/// `NonisolatedNonsendingByDefault` (SE-0461) lands: nonisolated async will
/// run on the caller's actor and main-actor callers get exclusivity for free.
public struct RefreshingExecutor<Operation> {
    @Binding var refreshTask: Task<Void, Never>?
    @Binding var accessToken: String?

    let executeOnce: (Operation) async throws -> Data
    let makeRefreshTask: () -> Task<Void, Never> // it will update access token
    let isUnauthorized: (ResponseError) -> Bool
    let needsAuth: (Operation) -> Bool

    public init(
        refreshTask: Binding<Task<Void, Never>?>,
        accessToken: Binding<String?>,
        executeOnce: @escaping (Operation) async throws -> Data,
        makeRefreshTask: @escaping () -> Task<Void, Never>,
        isUnauthorized: @escaping (ResponseError) -> Bool,
        needsAuth: @escaping (Operation) -> Bool
    ) {
        self._refreshTask = refreshTask
        self._accessToken = accessToken
        self.executeOnce = executeOnce
        self.makeRefreshTask = makeRefreshTask
        self.isUnauthorized = isUnauthorized
        self.needsAuth = needsAuth
    }

    public func executeWithRefresh(_ operation: Operation) async throws -> Data {
        guard needsAuth(operation) else {
            return try await executeOnce(operation)
        }
        let oldToken = accessToken
        var alreadyRefreshing = false
        if let refreshTask {
            alreadyRefreshing = true
            await refreshTask.value
        }
        do {
            return try await executeOnce(operation)
        } catch {
            guard !alreadyRefreshing,
                  let responseError = error as? ResponseError,
                  isUnauthorized(responseError)
            else {
                throw error
            }

            if let refreshTask {
                await refreshTask.value
            } else if oldToken == accessToken {
                refreshTask = makeRefreshTask()
                await refreshTask?.value
                refreshTask = nil
            }

            guard oldToken != accessToken else {
                throw error
            }

            return try await executeOnce(operation)
        }
    }
}
