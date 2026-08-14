import DeclarativeRequests
import Foundation
@testable import PetstoreAPI
import Testing

private let baseURL = URL(string: "http://petstore.swagger.io/v1")!

@Test func showPetByIdBuildsExpectedRequest() throws {
    let request = try SwaggerPetstoreEndpoint.showPetById(petId: "42")
        .base(baseURL)
        .request
    #expect(request.url?.absoluteString == "http://petstore.swagger.io/v1/pets/42")
    #expect(request.httpMethod == "GET")
}

@Test func listPetsWithLimitCarriesQueryItem() throws {
    let request = try SwaggerPetstoreEndpoint.listPets(limit: 10)
        .base(baseURL)
        .request
    #expect(request.url?.query == "limit=10")
    #expect(request.url?.absoluteString == "http://petstore.swagger.io/v1/pets?limit=10")
    #expect(request.httpMethod == "GET")
}

@Test func listPetsWithoutLimitCarriesNoQuery() throws {
    let request = try SwaggerPetstoreEndpoint.listPets(limit: nil)
        .base(baseURL)
        .request
    #expect(request.url?.query == nil)
    #expect(request.url?.absoluteString == "http://petstore.swagger.io/v1/pets")
}

@Test func createPetsIsJSONPost() throws {
    let request = try SwaggerPetstoreEndpoint.createPets(body: Pet(id: 1, name: "Rex"))
        .base(baseURL)
        .request
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "http://petstore.swagger.io/v1/pets")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.httpBody != nil)
}

@Test func defaultBaseURLComesFromSpecServers() {
    #expect(SwaggerPetstoreEndpoint.defaultBaseURL == baseURL)
}
