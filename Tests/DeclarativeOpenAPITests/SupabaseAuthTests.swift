import DeclarativeOpenAPIRuntime
import DeclarativeRequests
import Foundation
@testable import SupabaseAuthAPI
import SwiftUI
import Testing

private let projectBaseURL = URL(string: "https://myproject.supabase.co/auth/v1")!
private let client = SupabaseAuthClient(
    baseURL: projectBaseURL,
    apikey: .constant("anon-key"),
    accessToken: .constant("jwt-access-token"),
    refreshToken: .constant("4nYUCw0wZR_DNOTSDbSGMQ"),
    refreshTask: .constant(nil)
)

@Test func refreshSessionBuildsTokenRefreshRequest() throws {
    let request = try client.request(.postToken(grantType: .refreshToken, body: .init(refreshToken: "4nYUCw0wZR_DNOTSDbSGMQ")))

    #expect(request.url?.absoluteString
        == "https://myproject.supabase.co/auth/v1/token?grant_type=refresh_token")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")

    let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
    #expect(body == ["refresh_token": "4nYUCw0wZR_DNOTSDbSGMQ"])
}

@Test func userEndpointCarriesApikeyAndBearer() throws {
    let request = try client.request(.getUser)
    #expect(request.url?.absoluteString == "https://myproject.supabase.co/auth/v1/user")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-access-token")
}

@Test func userEndpointWithoutTokenFailsAtRequest() {
    let loggedOut = SupabaseAuthClient(baseURL: projectBaseURL, apikey: .constant("anon-key"), accessToken: .constant(nil), refreshToken: .constant(nil), refreshTask: .constant(nil))
    #expect(throws: SupabaseAuthRESTAPI.MissingUserAuth.self) {
        try loggedOut.request(.getUser)
    }
}

@Test func publicEndpointPassesWithNilTokenViaSecuritySection() throws {
    // One wire-once request(_:) serves every operation — the generated
    // Security gates decide which credentials are demanded.
    let loggedOut = SupabaseAuthClient(baseURL: projectBaseURL, apikey: .constant("anon-key"), accessToken: .constant(nil), refreshToken: .constant(nil), refreshTask: .constant(nil))
    let request = try loggedOut.request(.postSignup(body: .init()))
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func nilApikeyFailsAtRequest() {
    let unconfigured = SupabaseAuthClient(baseURL: projectBaseURL, apikey: .constant(nil), accessToken: .constant(nil), refreshToken: .constant(nil), refreshTask: .constant(nil))
    #expect(throws: SupabaseAuthRESTAPI.MissingAPIKeyAuth.self) {
        try unconfigured.request(.postSignup(body: .init()))
    }
}

@Test func keylessOperationCarriesNoApikeyEvenWhenConfigured() throws {
    let request = try client.request(.postSamlAcs(relayState: nil, sAMLArt: nil, sAMLResponse: nil))
    #expect(request.value(forHTTPHeaderField: "apikey") == nil)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func securitySectionMatchesSpec() {
    #expect(SupabaseAuthRESTAPI.Security.schemes(.getUser) == ["APIKeyAuth", "UserAuth"])
    #expect(SupabaseAuthRESTAPI.Security.schemes(.postToken(grantType: .password, body: .init()))
        == ["APIKeyAuth"])
    #expect(SupabaseAuthRESTAPI.Security.needsUserAuth(.getUser) == true)
    #expect(SupabaseAuthRESTAPI.Security.needsUserAuth(.postSignup(body: .init())) == false)
    #expect(SupabaseAuthRESTAPI.Security.needsAPIKeyAuth(
        .postSamlAcs(relayState: nil, sAMLArt: nil, sAMLResponse: nil)
    ) == false)
}

@Test func signupIsPlainKeyedJSONPost() throws {
    let request = try client.request(.postSignup(body: .init()))
    #expect(request.url?.absoluteString == "https://myproject.supabase.co/auth/v1/signup")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
}

@Test func adminOperationsAreNotGenerated() throws {
    let generated = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/SupabaseAuthAPI/SupabaseAuth.generated.swift"),
        encoding: .utf8
    )
    #expect(!generated.contains("case getAdminUsers"))
    #expect(!generated.contains("AdminAuth\""))
    #expect(generated.contains("// Client-only: operations requiring AdminAuth are not generated."))
}

@Test func templatedServerURLProducesNoDefaultBaseURL() throws {
    let generated = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/SupabaseAuthAPI/SupabaseAuth.generated.swift"),
        encoding: .utf8
    )
    #expect(!generated.contains("defaultBaseURL"))
    #expect(generated.contains("Server URL is templated"))
}

@Test func evaluatePassesDeclaredStatusAndFailsRateLimit() throws {
    let url = projectBaseURL
    let ok = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
    let tokens = Data(#"{"access_token":"t"}"#.utf8)
    #expect(try ResponseError.evaluate((tokens, ok), successStatuses: SupabaseAuthRESTAPI.Responses.successStatuses(.getUser)) == tokens)

    let limited = try #require(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: nil))
    // #expect(throws:) instead of do/catch-as: typed-throws calls inside a
    // catch-as pattern crash the Swift 6.3 SILGen verifier (fixed in 6.4).
    let error = #expect(throws: ResponseError.self) {
        try ResponseError.evaluate((Data(), limited), successStatuses: SupabaseAuthRESTAPI.Responses.successStatuses(.getUser))
    }
    #expect(error?.status == 429)
}

@Test func typedClientDecodesTokenRefreshResponse() async throws {
    let api = SupabaseAuthRESTAPI.Client.wired(
        execute: NetworkExecution(
            request: client.request,
            transport: { request in
                #expect(request.url?.query == "grant_type=refresh_token")
                return (Data(#"{"access_token":"new-jwt","refresh_token":"new-r"}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            successStatuses: SupabaseAuthRESTAPI.Responses.successStatuses
        ).execute,
        decoder: { _ in JSONDecoder() }
    )
    let session = try await api.postToken(.refreshToken, .init(refreshToken: "old-r"))
    #expect(session.accessToken == "new-jwt")
    #expect(session.refreshToken == "new-r")
}

final class RefreshHarness: @unchecked Sendable {
    var accessToken: String? = "expired"
    var refreshTask: Task<Void, Never>?
    var executions = 0
    var refreshes = 0
}

@Test func refreshingExecutorRefreshesOn401ThenRetriesOnce() async throws {
    let h = RefreshHarness()
    let executor = RefreshingExecutor<SupabaseAuthRESTAPI.Operation>(
        refreshTask: Binding(get: { h.refreshTask }, set: { h.refreshTask = $0 }),
        accessToken: Binding(get: { h.accessToken }, set: { h.accessToken = $0 }),
        executeOnce: { operation in
            h.executions += 1
            if h.accessToken == "fresh" { return Data("ok".utf8) }
            throw ResponseError(
                data: Data(),
                response: HTTPURLResponse(
                    url: projectBaseURL, statusCode: 401, httpVersion: nil, headerFields: nil
                )!
            )
        },
        refresh: {
            Task {
                h.refreshes += 1
                h.accessToken = "fresh"
            }
        },
        isUnauthorized: { $0.status == 401 },
        needsAuth: SupabaseAuthRESTAPI.Security.needsUserAuth
    )

    let data = try await executor.executeRefreshed(.getUser)
    #expect(String(decoding: data, as: UTF8.self) == "ok")
    #expect(h.executions == 2)   // failed attempt + one retry
    #expect(h.refreshes == 1)    // single-flight

    // second call: token already fresh — no refresh, one execution
    _ = try await executor.executeRefreshed(.getUser)
    #expect(h.executions == 3)
    #expect(h.refreshes == 1)
}

@Test func refreshingExecutorThrowsOriginalErrorWhenRefreshDoesNotHappen() async {
    let h = RefreshHarness()
    let executor = RefreshingExecutor<SupabaseAuthRESTAPI.Operation>(
        refreshTask: Binding(get: { h.refreshTask }, set: { h.refreshTask = $0 }),
        accessToken: Binding(get: { h.accessToken }, set: { h.accessToken = $0 }),
        executeOnce: { operation in
            throw ResponseError(
                data: Data(),
                response: HTTPURLResponse(
                    url: projectBaseURL, statusCode: 401, httpVersion: nil, headerFields: nil
                )!
            )
        },
        refresh: { Task { h.refreshes += 1 } },   // refresh runs but tokens unchanged
        isUnauthorized: { $0.status == 401 },
        needsAuth: SupabaseAuthRESTAPI.Security.needsUserAuth
    )
    await #expect(throws: ResponseError.self) {
        try await executor.executeRefreshed(.getUser)
    }
    #expect(h.refreshes == 1)
}

@Test func executorBypassesRefreshMachineryForPublicOperations() async {
    let h = RefreshHarness()
    let executor = RefreshingExecutor<SupabaseAuthRESTAPI.Operation>(
        refreshTask: Binding(get: { h.refreshTask }, set: { h.refreshTask = $0 }),
        accessToken: Binding(get: { h.accessToken }, set: { h.accessToken = $0 }),
        executeOnce: { operation in
            h.executions += 1
            throw ResponseError(
                data: Data(),
                response: HTTPURLResponse(
                    url: projectBaseURL, statusCode: 401, httpVersion: nil, headerFields: nil
                )!
            )
        },
        refresh: { Task { h.refreshes += 1 } },
        isUnauthorized: { $0.status == 401 },
        needsAuth: SupabaseAuthRESTAPI.Security.needsUserAuth
    )
    // postToken is public (no UserAuth): even a 401 must not touch the
    // refresh machinery — this is what makes refresh-through-api recursion-free.
    await #expect(throws: ResponseError.self) {
        try await executor.executeRefreshed(.postToken(grantType: .refreshToken, body: .init()))
    }
    #expect(h.executions == 1)
    #expect(h.refreshes == 0)
}
