import SwiftUI

/// 401 → single-flight refresh → one retry, generic over any spec's Operation.
///
/// Strategy: try to refresh; if refresh isn't possible or didn't happen, throw
/// the original error. Single-flight holds by the nil-gate: `refreshTask` stays
/// non-nil from creation until its creator clears it, so a second refresh can
/// never start while one is in flight. `alreadyRefreshing` doubles as the
/// staleness barrier: a call that joined a refresh ran with the fresh token,
/// so its failure escalates instead of re-refreshing.
@MainActor
struct Pseudo<Operation> {
    @Binding var refreshTask: Task<Void, Never>? // it will update refresh and/or access token
    @Binding var accessToken: String?

    let execute: @MainActor (Operation) async throws -> Data
    let refresh: @Sendable () async -> Void
    let isError401: (Error) -> Bool
    let needsAuth: (Operation) -> Bool

    func run(_ operation: Operation) async throws -> Data {
        let oldtoken = accessToken
        var alreadyRefreshing = false
        if let refreshTask {
            alreadyRefreshing = true
            await refreshTask.value
        }
        do {
            return try await execute(operation)
        } catch {
            guard !alreadyRefreshing, isError401(error), needsAuth(operation) else {
                throw error
            }

            if let refreshTask {
                await refreshTask.value
            } else if oldtoken == accessToken {
                let task = Task { [refresh] in
                    await refresh()
                }
                refreshTask = task
                await task.value
                refreshTask = nil
            }

            guard oldtoken != accessToken else { // not refreshed
                throw error
            }

            return try await execute(operation)
        }
    }
}
