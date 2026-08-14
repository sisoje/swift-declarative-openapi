import DeclarativeRequests
import Foundation
@testable import MuseumAPI
import Testing

private let museumBaseURL = URL(string: "https://redocly.com/_mock/docs/openapi/museum-api")!

@Test func getSpecialEventInterpolatesEventId() throws {
    let request = try RedoclyMuseumAPIEndpoint
        .getSpecialEvent(eventId: "3be6453c-03eb-4357-ae5a-984a0e574a54")
        .base(museumBaseURL)
        .request
    #expect(request.url?.absoluteString
        == "https://redocly.com/_mock/docs/openapi/museum-api/special-events/3be6453c-03eb-4357-ae5a-984a0e574a54")
    #expect(request.httpMethod == "GET")
}

@Test func listSpecialEventsCarriesOnlyProvidedQueryItems() throws {
    let request = try RedoclyMuseumAPIEndpoint
        .listSpecialEvents(startDate: "2023-02-23", endDate: nil, page: 2, limit: nil)
        .base(museumBaseURL)
        .request
    #expect(request.url?.query == "startDate=2023-02-23&page=2")
}

@Test func getTicketCodeBuildsNestedPath() throws {
    let request = try RedoclyMuseumAPIEndpoint
        .getTicketCode(ticketId: "a54a57ca-36f8-421b-a6b4-2e8f26858a4c")
        .base(museumBaseURL)
        .request
    #expect(request.url?.path.hasSuffix("/tickets/a54a57ca-36f8-421b-a6b4-2e8f26858a4c/qr") == true)
}

@Test func buyMuseumTicketsIsJSONPost() throws {
    let request = try RedoclyMuseumAPIEndpoint
        .buyMuseumTickets(body: BuyMuseumTickets())
        .base(museumBaseURL)
        .request
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.httpBody != nil)
}

@Test func deleteSpecialEventUsesDeleteMethod() throws {
    let request = try RedoclyMuseumAPIEndpoint
        .deleteSpecialEvent(eventId: "e1")
        .base(museumBaseURL)
        .request
    #expect(request.httpMethod == "DELETE")
}

@Test func documentLevelSecurityAppliesToEveryEndpoint() {
    #expect(RedoclyMuseumAPIEndpoint.getMuseumHours(startDate: nil, page: nil, limit: nil).securitySchemes
        == ["MuseumPlaceholderAuth"])
    #expect(RedoclyMuseumAPIEndpoint.deleteSpecialEvent(eventId: "e1").needsMuseumPlaceholderAuth == true)
}
