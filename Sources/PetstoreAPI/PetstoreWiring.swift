// Hand-written layer over Petstore.generated.swift — the degenerate wiring:
// the spec declares no security, so the client carries only the environment.

import DeclarativeOpenAPIRuntime
import DeclarativeRequests
import Foundation

struct PetstoreClient: Sendable {
    var baseURL: URL

    /// The (Operation) → Data seam: this app's request building and transport,
    /// gated by the generated status table.
    var execution: NetworkExecution<SwaggerPetstore.Operation> {
        NetworkExecution(
            request: { try $0.base(baseURL).request() },
            transport: { try await URLSession.shared.data(for: $0) },
            successStatuses: SwaggerPetstore.Responses.successStatuses
        )
    }

    var api: SwaggerPetstore.Client {
        .wired(execute: execution.execute) { _ in JSONDecoder() }
    }
}
