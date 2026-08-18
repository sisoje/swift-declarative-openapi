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
/// The gate is pinned to the isolation the executor was CONSTRUCTED in
/// (`#isolation` captured at init, the same trick SwiftUI's
/// `Binding(get:set:)` uses via `@_inheritActorContext`): every caller,
/// main or background, hops to that actor for the gate's read-check-set
/// (no suspension point inside it), so single-flight is global and the
/// bindings are only ever touched where they live — a binding built on
/// MainActor traps if touched anywhere else. Built in a nonisolated
/// context, `home` is nil and the gate degrades to caller-following.
/// The wire work stays off the actor: executeOnce leaves it when awaited.
public struct RefreshingExecutor<Operation: Sendable>: Sendable {
    @Binding var refreshTask: Task<Void, Never>?
    @Binding var accessToken: String?

    let executeOnce: @Sendable (Operation) async throws -> Data
    let makeRefreshTask: @Sendable () -> Task<Void, Never> // it will update access token
    let isUnauthorized: @Sendable (ResponseError) -> Bool
    let needsAuth: @Sendable (Operation) -> Bool

    /// The isolation the gate runs on, captured from the construction site.
    let initIsolation: (any Actor)?

    public init(
        refreshTask: Binding<Task<Void, Never>?>,
        accessToken: Binding<String?>,
        executeOnce: @escaping @Sendable (Operation) async throws -> Data,
        makeRefreshTask: @escaping @Sendable () -> Task<Void, Never>,
        isUnauthorized: @escaping @Sendable (ResponseError) -> Bool,
        needsAuth: @escaping @Sendable (Operation) -> Bool,
        isolation: isolated (any Actor)? = #isolation
    ) {
        self._refreshTask = refreshTask
        self._accessToken = accessToken
        self.executeOnce = executeOnce
        self.makeRefreshTask = makeRefreshTask
        self.isUnauthorized = isUnauthorized
        self.needsAuth = needsAuth
        self.initIsolation = isolation
    }

    public func executeWithRefresh(_ operation: Operation) async throws -> Data {
        guard needsAuth(operation) else {
            return try await executeOnce(operation)
        }
        return try await gate(operation, isolation: initIsolation)
    }

    /// The refresh gate, isolated to the construction actor by parameter.
    private func gate(_ operation: Operation, isolation: isolated (any Actor)?) async throws -> Data {
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
