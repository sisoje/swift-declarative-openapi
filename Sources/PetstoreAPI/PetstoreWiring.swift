// Hand-written layer over Petstore.generated.swift — the degenerate wiring:
// the spec declares no security, so the client carries only the environment.

import DeclarativeOpenAPIRuntime
import DeclarativeRequests
import Foundation

struct PetstoreClient {
    var baseURL: URL

    func request(_ operation: SwaggerPetstore.Operation) throws -> URLRequest {
        try operation.base(baseURL).request()
    }

    // Fully typed surface over this wiring: SwaggerPetstore.Client field per
    // operation, defaults to the real transport.

    /// URLSession as the transport closure — this app's transport policy.
    private func urlSessionTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    /// Every operation decodes with a plain `JSONDecoder` — this app's decoding policy.
    private func plainDecoder(_: SwaggerPetstore.Operation) -> JSONDecoder {
        JSONDecoder()
    }

    var api: SwaggerPetstore.Client {
        .wired(
            execute: NetworkExecution(request: request, transport: urlSessionTransport, evaluate: SwaggerPetstore.Responses.evaluate).execute,
            decoder: plainDecoder
        )
    }
}
