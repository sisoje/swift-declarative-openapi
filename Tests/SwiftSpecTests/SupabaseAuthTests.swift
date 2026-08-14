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
        .keyed(apikey: "anon-key")
        .authorized(accessToken: "jwt-access-token")
        .base(projectBaseURL)
        .request

    #expect(request.url?.absoluteString == "https://myproject.supabase.co/auth/v1/user")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-access-token")
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
