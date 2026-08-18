import BinanceAPI
import DeclarativeOpenAPIRuntime
import DeclarativeRequests
import MuseumAPI
import PetstoreAPI
import SupabaseAuthAPI
import Foundation
import Testing

/// Compile-time only: a public type gets no `Sendable` inference, so the
/// conformance has to be stated and can be silently lost. These calls fail
/// to compile if it ever is.
private func requiresSendable(_: some Sendable) {}

@Test func generatedSurfaceIsSendable() {
    // Operations conform via RequestBuildable — they cross into tasks and
    // are stored by wirings that hold them for a retry.
    requiresSendable(SwaggerPetstore.Operation.showPetById(petId: "42"))
    requiresSendable(RedoclyMuseumAPI.Operation.getMuseumHours(startDate: nil, page: nil, limit: nil))
    requiresSendable(SupabaseAuthRESTAPI.Operation.getHealth)

    // The client is one value an app holds for its lifetime — a global, an
    // @Environment value, something an actor owns.
    requiresSendable(SwaggerPetstore.Client.wired(execute: { _ in Data() }, decoder: { _ in JSONDecoder() }))
    requiresSendable(SupabaseAuthRESTAPI.Client.wired(execute: { _ in Data() }, decoder: { _ in JSONDecoder() }))

    // Models are decoded responses: cached, held in globals, sent to actors.
    requiresSendable(SwaggerPetstore.Pet(id: 1, name: "Rex"))
    requiresSendable(SwaggerPetstore.APIError(code: 1, message: "x"))
}


/// Decoding is off the main actor by contract, not by the current language
/// default: `ClientBuilder.decode` is `@concurrent` (SE-0461), so even a
/// main-actor caller — and even under `NonisolatedNonsendingByDefault` —
/// never runs JSONDecoder on the UI thread. The decoder factory executes
/// inside that step, so it witnesses the executor.
@Test @MainActor func decodingRunsOffTheMainActor() async throws {
    let api = SwaggerPetstore.Client.wired(
        execute: { _ in Data(#"{"id": 1, "name": "Rex"}"#.utf8) },
        decoder: { _ in
            #expect(!Thread.isMainThread)
            return JSONDecoder()
        }
    )
    let pet = try await api.showPetById("42")
    #expect(pet.name == "Rex")
}

/// Request building is wire work — URL composition and JSON body encoding —
/// so `NetworkExecution.execute` is `@concurrent`: a main-actor caller never
/// builds a request on the UI thread. The request closure runs inside that
/// seam, so it witnesses the executor.
@Test @MainActor func requestBuildingRunsOffTheMainActor() async throws {
    let seam = NetworkExecution<SwaggerPetstore.Operation>(
        request: { operation in
            #expect(!Thread.isMainThread)
            return try operation.base(URL(string: "https://example.com")!).request()
        },
        transport: { request in
            (Data(#"{"id": 1, "name": "Rex"}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        },
        successStatuses: SwaggerPetstore.Responses.successStatuses
    )
    let api = SwaggerPetstore.Client.wired(execute: seam.execute, decoder: { _ in JSONDecoder() })
    let pet = try await api.showPetById("42")
    #expect(pet.id == 1)
}
