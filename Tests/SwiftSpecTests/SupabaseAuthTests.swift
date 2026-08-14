import DeclarativeRequests
import Foundation
@testable import SupabaseAuthAPI
import Testing

private let projectBaseURL = URL(string: "https://myproject.supabase.co/auth/v1")!

@Test func refreshSessionBuildsTokenRefreshRequest() throws {
    let request = try SupabaseAuthRESTAPIEndpoint
        .refreshSession(refreshToken: "4nYUCw0wZR_DNOTSDbSGMQ")
        .keyed(apikey: "anon-key")
        .base(projectBaseURL)
        .request

    #expect(request.url?.absoluteString
        == "https://myproject.supabase.co/auth/v1/token?grant_type=refresh_token")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")

    let body = try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
    #expect(body == ["refresh_token": "4nYUCw0wZR_DNOTSDbSGMQ"])
}

@Test func userEndpointCarriesApikeyAndBearer() throws {
    let request = try SupabaseAuthRESTAPIEndpoint
        .getUser
        .authorized(accessToken: "jwt-access-token")
        .keyed(apikey: "anon-key")
        .base(projectBaseURL)
        .request

    #expect(request.url?.absoluteString == "https://myproject.supabase.co/auth/v1/user")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-access-token")
}

@Test func refreshWithoutStoredTokenFailsAtRequest() {
    #expect(throws: SupabaseAuthRESTAPIEndpoint.MissingRefreshToken.self) {
        try SupabaseAuthRESTAPIEndpoint
            .refreshSession(refreshToken: nil)
            .keyed(apikey: "anon-key")
            .base(projectBaseURL)
            .request
    }
}

@Test func userEndpointWithoutTokenFailsAtRequest() {
    #expect(throws: MissingAccessToken.self) {
        try SupabaseAuthRESTAPIEndpoint
            .getUser
            .authorized(accessToken: nil)
            .keyed(apikey: "anon-key")
            .base(projectBaseURL)
            .request
    }
}

@Test func callerGatesAuthorizedOnGeneratedFlag() {
    // Public endpoints don't chain .authorized — the generated flag is the
    // caller's gate, same rule as .keyed for keyless endpoints.
    #expect(SupabaseAuthRESTAPIEndpoint.postSignup(body: PostSignupBody()).needsUserAuth == false)
    #expect(SupabaseAuthRESTAPIEndpoint.getUser.needsUserAuth == true)
}

@Test func nilApikeyFailsAtRequest() {
    #expect(throws: MissingAPIKey.self) {
        try SupabaseAuthRESTAPIEndpoint
            .postSignup(body: PostSignupBody())
            .keyed(apikey: nil)
            .base(projectBaseURL)
            .request
    }
}

@Test func keylessEndpointSkipsKeyedEntirely() throws {
    let request = try SupabaseAuthRESTAPIEndpoint
        .postSamlAcs(relayState: nil, sAMLArt: nil, sAMLResponse: nil)
        .base(projectBaseURL)
        .request
    #expect(request.value(forHTTPHeaderField: "apikey") == nil)
}

@Test func generatedPerSchemeFlagsMatchSpec() {
    #expect(SupabaseAuthRESTAPIEndpoint.getUser.needsUserAuth == true)
    #expect(SupabaseAuthRESTAPIEndpoint.getUser.needsAPIKeyAuth == true)
    #expect(SupabaseAuthRESTAPIEndpoint.postSamlAcs(relayState: nil, sAMLArt: nil, sAMLResponse: nil)
        .needsAPIKeyAuth == false)
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

@Test func generatedSecurityMatchesSpec() {
    #expect(SupabaseAuthRESTAPIEndpoint.getUser.securitySchemes == ["APIKeyAuth", "UserAuth"])
    #expect(SupabaseAuthRESTAPIEndpoint.postToken(grantType: "password", body: PostTokenBody()).securitySchemes
        == ["APIKeyAuth"])
    #expect(SupabaseAuthRESTAPIEndpoint.postSamlAcs(relayState: nil, sAMLArt: nil, sAMLResponse: nil)
        .securitySchemes.isEmpty)
}

@Test func signupIsPlainKeyedJSONPost() throws {
    let request = try SupabaseAuthRESTAPIEndpoint
        .postSignup(body: PostSignupBody())
        .keyed(apikey: "anon-key")
        .base(projectBaseURL)
        .request

    #expect(request.url?.absoluteString == "https://myproject.supabase.co/auth/v1/signup")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
}

@Test func templatedServerURLProducesNoDefaultBaseURL() throws {
    let generated = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/SupabaseAuthAPI/SupabaseAuth.generated.swift"),
        encoding: .utf8
    )
    #expect(!generated.contains("defaultBaseURL"))
    #expect(generated.contains("Server URL is templated"))
}
