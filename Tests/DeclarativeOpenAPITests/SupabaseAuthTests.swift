import DeclarativeRequests
import Foundation
@testable import SupabaseAuthAPI
import Testing

private let projectBaseURL = URL(string: "https://myproject.supabase.co/auth/v1")!
private let client = SupabaseAuthClient(
    baseURL: projectBaseURL,
    apikey: "anon-key",
    accessToken: "jwt-access-token"
)

@Test func refreshSessionBuildsTokenRefreshRequest() throws {
    let request = try client.refreshSessionRequest(refreshToken: "4nYUCw0wZR_DNOTSDbSGMQ")

    #expect(request.url?.absoluteString
        == "https://myproject.supabase.co/auth/v1/token?grant_type=refresh_token")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")

    let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
    #expect(body == ["refresh_token": "4nYUCw0wZR_DNOTSDbSGMQ"])
}

@Test func refreshWithoutStoredTokenFails() {
    #expect(throws: MissingRefreshToken.self) {
        try client.refreshSessionRequest(refreshToken: nil)
    }
}

@Test func userEndpointCarriesApikeyAndBearer() throws {
    let request = try client.request(.getUser)
    #expect(request.url?.absoluteString == "https://myproject.supabase.co/auth/v1/user")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-access-token")
}

@Test func userEndpointWithoutTokenFailsAtRequest() {
    let loggedOut = SupabaseAuthClient(baseURL: projectBaseURL, apikey: "anon-key")
    #expect(throws: MissingAccessToken.self) {
        try loggedOut.request(.getUser)
    }
}

@Test func publicEndpointPassesWithNilTokenViaSecuritySection() throws {
    // One wire-once request(_:) serves every operation — the generated
    // Security gates decide which credentials are demanded.
    let loggedOut = SupabaseAuthClient(baseURL: projectBaseURL, apikey: "anon-key")
    let request = try loggedOut.request(.postSignup(body: .init()))
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func nilApikeyFailsAtRequest() {
    let unconfigured = SupabaseAuthClient(baseURL: projectBaseURL)
    #expect(throws: MissingAPIKey.self) {
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
        .postSamlAcs(relayState: nil, sAMLArt: nil, sAMLResponse: nil)) == false)
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
