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
/// `executeWithRefresh` is `nonisolated(nonsending)` (SE-0461): it runs on
/// the caller's actor, and the gate's read-check-set has no suspension
/// point inside it, so callers sharing one actor — the main-actor UI this
/// is built for — get an atomic gate. That closes the SE-0338 caveat this
/// comment used to carry. Callers spread across different isolation
/// domains still race the gate; single-flight is per-actor, not global.
public struct RefreshingExecutor<Operation: Sendable>: Sendable {
    @Binding var refreshTask: Task<Void, Never>?
    @Binding var accessToken: String?

    let executeOnce: @Sendable (Operation) async throws -> Data
    let makeRefreshTask: @Sendable () -> Task<Void, Never> // it will update access token
    let isUnauthorized: @Sendable (ResponseError) -> Bool
    let needsAuth: @Sendable (Operation) -> Bool

    public init(
        refreshTask: Binding<Task<Void, Never>?>,
        accessToken: Binding<String?>,
        executeOnce: @escaping @Sendable (Operation) async throws -> Data,
        makeRefreshTask: @escaping @Sendable () -> Task<Void, Never>,
        isUnauthorized: @escaping @Sendable (ResponseError) -> Bool,
        needsAuth: @escaping @Sendable (Operation) -> Bool
    ) {
        self._refreshTask = refreshTask
        self._accessToken = accessToken
        self.executeOnce = executeOnce
        self.makeRefreshTask = makeRefreshTask
        self.isUnauthorized = isUnauthorized
        self.needsAuth = needsAuth
    }

    nonisolated(nonsending) public func executeWithRefresh(_ operation: Operation) async throws -> Data {
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
