// Hand-written layer over Petstore.generated.swift — the degenerate wiring:
// the spec declares no security, so the client carries only the environment.

import DeclarativeRequests
import Foundation


/// URLSession as the transport closure: `URLRequest` in, `(Data, URLResponse)` out.
func urlSessionTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
    try await URLSession.shared.data(for: request)
}

/// Every operation decodes with a plain `JSONDecoder` — swap this when one doesn't.
func plainDecoder(_ operation: SwaggerPetstore.Operation) -> JSONDecoder {
    JSONDecoder()
}

struct PetstoreClient {
    var baseURL: URL

    func request(_ operation: SwaggerPetstore.Operation) throws -> URLRequest {
        try operation.base(baseURL).request()
    }

    /// Fully typed surface over this wiring: SwaggerPetstore.Client field per
    /// operation, defaults to the real transport.
    var api: SwaggerPetstore.Client {
        .wired(request: request, transport: urlSessionTransport, decoder: plainDecoder)
    }
}
