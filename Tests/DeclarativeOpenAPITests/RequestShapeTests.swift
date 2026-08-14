import DeclarativeRequests
import Foundation
@testable import PetstoreAPI
import Testing

private let baseURL = URL(string: "http://petstore.swagger.io/v1")!

@Test func showPetByIdBuildsExpectedRequest() throws {
    let request = try SwaggerPetstore.Operation.showPetById(petId: "42")
        .base(baseURL)
        .request()
    #expect(request.url?.absoluteString == "http://petstore.swagger.io/v1/pets/42")
    #expect(request.httpMethod == "GET")
}

@Test func listPetsWithLimitCarriesQueryItem() throws {
    let request = try SwaggerPetstore.Operation.listPets(limit: 10)
        .base(baseURL)
        .request()
    #expect(request.url?.query == "limit=10")
    #expect(request.url?.absoluteString == "http://petstore.swagger.io/v1/pets?limit=10")
    #expect(request.httpMethod == "GET")
}

@Test func listPetsWithoutLimitCarriesNoQuery() throws {
    let request = try SwaggerPetstore.Operation.listPets(limit: nil)
        .base(baseURL)
        .request()
    #expect(request.url?.query == nil)
    #expect(request.url?.absoluteString == "http://petstore.swagger.io/v1/pets")
}

@Test func createPetsIsJSONPost() throws {
    let request = try SwaggerPetstore.Operation.createPets(body: .init(id: 1, name: "Rex"))
        .base(baseURL)
        .request()
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "http://petstore.swagger.io/v1/pets")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.httpBody != nil)
}

@Test func defaultBaseURLComesFromSpecServers() {
    #expect(SwaggerPetstore.defaultBaseURL == baseURL)
}

@Test func clientCarriesOnlyEnvironment() throws {
    let client = PetstoreClient(baseURL: baseURL)
    let request = try client.request(.showPetById(petId: "42"))
    #expect(request.url?.absoluteString == "http://petstore.swagger.io/v1/pets/42")
    #expect(request.allHTTPHeaderFields?.isEmpty ?? true)
}

@Test func typedClientDecodesThroughStubTransport() async throws {
    let api = SwaggerPetstore.Client.wired(
        execute: SwaggerPetstore.Client.execution(request: PetstoreClient(baseURL: baseURL).request,
        transport: { request in
            (Data(#"{"id":7,"name":"Rex"}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }),
        decoder: { _ in JSONDecoder() }
    )
    let pet = try await api.showPetById("7")
    #expect(pet.id == 7)
    #expect(pet.name == "Rex")
}

@Test func typedClientFieldsAreStubbable() async throws {
    var api = SwaggerPetstore.Client.wired(
        execute: SwaggerPetstore.Client.execution(request: PetstoreClient(baseURL: baseURL).request,
        transport: { try await URLSession.shared.data(for: $0) }),
        decoder: { _ in JSONDecoder() }
    )
    api.showPetById = { _ in SwaggerPetstore.Pet(id: 1, name: "Stub") }
    let pet = try await api.showPetById("anything")
    #expect(pet.name == "Stub")
}
