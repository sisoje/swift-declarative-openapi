import DeclarativeOpenAPIRuntime
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

@Test func clientAttachesBasicAuthEverywhere() throws {
    let client = MuseumClient(baseURL: museumBaseURL, credentials: (username: "curator", password: "secret"))
    let request = try client.request(.getMuseumHours(startDate: nil, page: nil, limit: nil))
    let expected = "Basic " + Data("curator:secret".utf8).base64EncodedString()
    #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
    #expect(request.url?.absoluteString == "https://redocly.com/_mock/docs/openapi/museum-api/museum-hours")
}

@Test func clientWithoutCredentialsFailsAtRequest() {
    let client = MuseumClient(baseURL: museumBaseURL)
    #expect(throws: RedoclyMuseumAPI.MissingMuseumPlaceholderAuth.self) {
        try client.request(.getMuseumHours(startDate: nil, page: nil, limit: nil))
    }
}

@Test func evaluateReturnsPayloadOnDeclaredStatus() throws {
    let payload = Data("[]".utf8)
    let response = try #require(HTTPURLResponse(
        url: museumBaseURL, statusCode: 204, httpVersion: nil, headerFields: nil
    ))
    let data = try RedoclyMuseumAPI.Responses.evaluate(.deleteSpecialEvent(eventId: "e1"), (payload, response))
    #expect(data == payload)
}

@Test func evaluateRejectsUndeclaredSuccessStatus() throws {
    // deleteSpecialEvent declares 204 — a 200 is not an expected shape.
    let response = try #require(HTTPURLResponse(
        url: museumBaseURL, statusCode: 200, httpVersion: nil, headerFields: nil
    ))
    #expect(throws: ResponseError<RedoclyMuseumAPI.Operation>.self) {
        try RedoclyMuseumAPI.Responses.evaluate(.deleteSpecialEvent(eventId: "e1"), (Data(), response))
    }
}

@Test func nextLayerDecodesTypedErrorFromResponseError() throws {
    // The museum's typed error is decoded by the layer that wants it, from
    // the error's own lossless data — evaluate never guesses.
    let errorBody = Data(#"{"type":"validation","title":"Validation failed"}"#.utf8)
    let response = try #require(HTTPURLResponse(
        url: museumBaseURL, statusCode: 400, httpVersion: nil, headerFields: nil
    ))
    do {
        _ = try RedoclyMuseumAPI.Responses.evaluate(.getSpecialEvent(eventId: "bad"), (errorBody, response))
        Issue.record("expected ResponseError")
    } catch let error as ResponseError<RedoclyMuseumAPI.Operation> {
        #expect(error.status == 400)
        let typed = try JSONDecoder().decode(RedoclyMuseumAPI.APIError.self, from: error.data)
        #expect(typed.title == "Validation failed")
        #expect(typed.type == "validation")
    }
}

@Test func wiredClientComposesLayersThroughInjectedTransport() async throws {
    let wiring = MuseumClient(baseURL: museumBaseURL, credentials: (username: "u", password: "p"))
    let api = RedoclyMuseumAPI.Client.wired(
        execute: RedoclyMuseumAPI.Client.execution(request: wiring.request,
        transport: { request in
            #expect(request.url?.path.hasSuffix("/museum-hours") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
            return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }),
        decoder: { _ in JSONDecoder() }
    )
    let hours = try await api.getMuseumHours(nil, nil, nil)
    #expect(hours.isEmpty)
}

@Test func wiredClientSurfacesResponseError() async {
    let wiring = MuseumClient(baseURL: museumBaseURL, credentials: (username: "u", password: "p"))
    let api = RedoclyMuseumAPI.Client.wired(
        execute: RedoclyMuseumAPI.Client.execution(request: wiring.request,
        transport: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }),
        decoder: { _ in JSONDecoder() }
    )
    await #expect(throws: ResponseError<RedoclyMuseumAPI.Operation>.self) {
        try await api.deleteSpecialEvent("e1")
    }
}

@Test func nonHTTPResponseThrowsItsOwnLosslessError() {
    let plain = URLResponse(
        url: museumBaseURL, mimeType: nil, expectedContentLength: 0, textEncodingName: nil
    )
    #expect(throws: ResponseError<RedoclyMuseumAPI.Operation>.self) {
        try RedoclyMuseumAPI.Responses.evaluate(.getSpecialEvent(eventId: "e1"), (Data("x".utf8), plain))
    }
}

@Test func typedClientVoidOperationSucceedsOn204() async throws {
    let wiring = MuseumClient(baseURL: museumBaseURL, credentials: (username: "u", password: "p"))
    let api = RedoclyMuseumAPI.Client.wired(
        execute: RedoclyMuseumAPI.Client.execution(request: wiring.request,
        transport: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!)
        }),
        decoder: { _ in JSONDecoder() }
    )
    try await api.deleteSpecialEvent("e1") // returns Void, throws on anything but 204
}
