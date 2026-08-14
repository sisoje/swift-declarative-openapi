import SwiftUI

struct Pseudo<OP> {
    @Binding var refreshTask: Task<Void, Never>? // it will update refresh and or access token
    @Binding var accessToken: String?

    let closure: (OP) async throws -> Data
    let refreshprocess: @Sendable () async -> Void
    let isError401: (Error) -> Bool
    let needsAuth: (OP) -> Bool

    func doit(_ operation: OP) async throws -> Data {
        let oldtoken = accessToken
        var alreadyRefreshing = false
        if let refreshTask {
            alreadyRefreshing = true
            await refreshTask.value
        }
        do {
            return try await closure(operation)
        } catch {
            guard !alreadyRefreshing else {
                throw error
            }
            guard isError401(error) else {
                throw error
            }
            guard needsAuth(operation) else {
                throw error
            }

            if let refreshTask {
                await refreshTask.value
            } else if oldtoken == accessToken {
                let task = Task { [refreshprocess] in
                    await refreshprocess()
                }
                refreshTask = task
                await task.value
                refreshTask = nil
            }
            
            if oldtoken == accessToken {
                throw error
            }
            
            return try await closure(operation)
        }
    }
}
