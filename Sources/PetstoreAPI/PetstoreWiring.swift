// Hand-written layer over Petstore.generated.swift — the degenerate wiring:
// the spec declares no security, so the client carries only the environment.

import DeclarativeRequests
import Foundation

struct PetstoreClient {
    var baseURL: URL

    func request(_ operation: SwaggerPetstore.Operation) throws -> URLRequest {
        try operation.base(baseURL).request()
    }
}
