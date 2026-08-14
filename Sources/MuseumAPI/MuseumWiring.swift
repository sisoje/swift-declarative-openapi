// Hand-written layer over Museum.generated.swift — minimal wiring: the spec
// declares one basic-auth scheme document-wide, so every operation is gated
// the same way, through the generated Security section.

import DeclarativeRequests
import Foundation

struct MissingCredentials: Error {}

/// Session + environment in one place. Credentials are optional so the
/// client is constructible before any exist — a required-but-missing pair
/// fails the build at `request(_:)`.
struct MuseumClient {
    var baseURL: URL
    var username: String?
    var password: String?

    func request(_ operation: RedoclyMuseumAPI.Operation) throws -> URLRequest {
        try RequestBlock {
            operation
            BaseURL(baseURL)
            if RedoclyMuseumAPI.Security.needsMuseumPlaceholderAuth(operation) {
                if let username, let password {
                    RedoclyMuseumAPI.Security.museumPlaceholderAuth(username: username, password: password)
                } else {
                    RequestFailure(MissingCredentials())
                }
            }
        }.request()
    }
}
