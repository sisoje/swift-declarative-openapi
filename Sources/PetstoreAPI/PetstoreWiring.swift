// Hand-written layer over Petstore.generated.swift — the degenerate wiring:
// the spec declares no security, so the client carries only the environment.

import DeclarativeRequests
import Foundation


struct PetstoreClient {
    var baseURL: URL

    func request(_ operation: SwaggerPetstore.Operation) throws -> URLRequest {
        try operation.base(baseURL).request()
    }

    /// Fully typed surface over this wiring: SwaggerPetstore.Client field per
    /// operation, defaults to the real transport.
    var api: SwaggerPetstore.Client {
        .wired(
            request: request,
            transport: SwaggerPetstore.Client.urlSessionTransport,
            decoder: SwaggerPetstore.Client.plainDecoder
        )
    }
}
