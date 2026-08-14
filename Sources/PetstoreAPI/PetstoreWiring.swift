// Hand-written layer over Petstore.generated.swift — the degenerate wiring:
// the spec declares no security, so the client carries only the environment.

import DeclarativeRequests
import Foundation

struct PetstoreClient {
    var baseURL: URL

    func request(_ operation: SwaggerPetstore.Operation) throws -> URLRequest {
        try operation.base(baseURL).request()
    }

    /// request → execute → evaluate: each layer separable — build the
    /// request yourself, or hand a transport result straight to
    /// `SwaggerPetstore.Responses.evaluate`.
    func send(_ operation: SwaggerPetstore.Operation, using session: URLSession = .shared) async throws -> Data {
        let (data, response) = try await session.data(for: request(operation))
        return try SwaggerPetstore.Responses.evaluate(operation, (data, response as! HTTPURLResponse))
    }
}
