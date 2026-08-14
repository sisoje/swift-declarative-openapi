import DeclarativeRequests
import Foundation
@testable import MuseumAPI
import Testing

private let museumBaseURL = URL(string: "https://redocly.com/_mock/docs/openapi/museum-api")!

@Test func getSpecialEventInterpolatesEventId() throws {
    let request = try RedoclyMuseumAPI.Operation
        .getSpecialEvent(eventId: "3be6453c-03eb-4357-ae5a-984a0e574a54")
        .base(museumBaseURL)
        .request()
    #expect(request.url?.absoluteString
        == "https://redocly.com/_mock/docs/openapi/museum-api/special-events/3be6453c-03eb-4357-ae5a-984a0e574a54")
    #expect(request.httpMethod == "GET")
}

@Test func listSpecialEventsCarriesOnlyProvidedQueryItems() throws {
    let request = try RedoclyMuseumAPI.Operation
        .listSpecialEvents(startDate: "2023-02-23", endDate: nil, page: 2, limit: nil)
        .base(museumBaseURL)
        .request()
    #expect(request.url?.query == "startDate=2023-02-23&page=2")
}

@Test func getTicketCodeBuildsNestedPath() throws {
    let request = try RedoclyMuseumAPI.Operation
        .getTicketCode(ticketId: "a54a57ca-36f8-421b-a6b4-2e8f26858a4c")
        .base(museumBaseURL)
        .request()
    #expect(request.url?.path.hasSuffix("/tickets/a54a57ca-36f8-421b-a6b4-2e8f26858a4c/qr") == true)
}

@Test func buyMuseumTicketsIsJSONPost() throws {
    let request = try RedoclyMuseumAPI.Operation
        .buyMuseumTickets(body: .init(ticketDate: "2023-09-07", ticketType: .general))
        .base(museumBaseURL)
        .request()
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.httpBody != nil)
}

@Test func deleteSpecialEventUsesDeleteMethod() throws {
    let request = try RedoclyMuseumAPI.Operation
        .deleteSpecialEvent(eventId: "e1")
        .base(museumBaseURL)
        .request()
    #expect(request.httpMethod == "DELETE")
}

@Test func documentLevelSecurityAppliesToEveryEndpoint() {
    #expect(RedoclyMuseumAPI.Security.schemes(.getMuseumHours(startDate: nil, page: nil, limit: nil))
        == ["MuseumPlaceholderAuth"])
    #expect(RedoclyMuseumAPI.Security.needsMuseumPlaceholderAuth(.deleteSpecialEvent(eventId: "e1")) == true)
}
