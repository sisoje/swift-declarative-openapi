// Hand-written layer over Petstore.generated.swift — the degenerate wiring:
// the spec declares no security, so the client carries only the environment.

import DeclarativeRequests
import Foundation

struct PetstoreClient {
    var baseURL: URL

    func request(_ operation: SwaggerPetstore.Operation) throws -> URLRequest {
        try operation.base(baseURL).request()
    }

    /// request → execute → evaluate: each layer separable. The transport is
    /// just a closure — `URLRequest` in, `(Data, URLResponse)` out — inject
    /// URLSession, a stub, or anything else.
    func send(
        _ operation: SwaggerPetstore.Operation,
        transport: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) async throws -> Data {
        let (data, response) = try await transport(request(operation))
        return try SwaggerPetstore.Responses.evaluate(operation, (data, response))
    }
    /// Fully typed surface over this wiring: SwaggerPetstore.Client field per
    /// operation, defaults to the real transport.
    var api: SwaggerPetstore.Client {
        .wired(
            request: request,
            transport: { try await URLSession.shared.data(for: $0) },
            decoder: { _ in JSONDecoder() }
        )
    }
}
