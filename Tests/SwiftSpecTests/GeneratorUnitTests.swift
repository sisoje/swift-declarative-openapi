import Foundation
@testable import SwiftSpecCore
import Testing

// MARK: - Name sanitization

@Test func camelIdentifierSanitization() {
    #expect(camelIdentifier("listPets") == "listPets")
    #expect(camelIdentifier("show-pet-by-id") == "showPetById")
    #expect(camelIdentifier("Show Pet By Id!") == "showPetById")
    #expect(camelIdentifier("get_user.profile") == "getUserProfile")
}

@Test func pascalIdentifierSanitization() {
    #expect(pascalIdentifier("Swagger Petstore") == "SwaggerPetstore")
    #expect(pascalIdentifier("my-cool api v2") == "MyCoolApiV2")
}

@Test func fallbackCaseNameFromMethodAndPath() {
    #expect(fallbackCaseName(method: "get", path: "/pets/{petId}") == "getPetsPetId")
    #expect(fallbackCaseName(method: "POST", path: "/pets") == "postPets")
}

// MARK: - Type mapping

@Test func schemaTypeMapping() {
    #expect(swiftType(for: ["type": "string"]) == "String")
    #expect(swiftType(for: ["type": "integer"]) == "Int")
    #expect(swiftType(for: ["type": "number"]) == "Double")
    #expect(swiftType(for: ["type": "boolean"]) == "Bool")
    #expect(swiftType(for: ["type": "array", "items": ["type": "integer"]]) == "[Int]")
    #expect(swiftType(for: ["$ref": "#/components/schemas/Pet"]) == "Pet")
    #expect(swiftType(for: nil) == "String")
}

// MARK: - Path handling

@Test func leadingSlashStripping() {
    #expect(stripLeadingSlash("/pets") == "pets")
    #expect(stripLeadingSlash("pets") == "pets")
    #expect(stripLeadingSlash("/") == "")
}

// MARK: - Whole-document behaviors

@Test func requiredQueryParamIsNotWrappedInIfLet() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /things:
        get:
          operationId: listThings
          parameters:
            - name: kind
              in: query
              required: true
              schema:
                type: string
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("case listThings(kind: String)"))
    #expect(generated.contains("Query(\"kind\", kind)"))
    #expect(!generated.contains("if let kind"))
}

@Test func optionalQueryParamIsWrappedInIfLet() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /things:
        get:
          operationId: listThings
          parameters:
            - name: limit
              in: query
              required: false
              schema:
                type: integer
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("case listThings(limit: Int?)"))
    #expect(generated.contains("if let limit {"))
    #expect(generated.contains("Query(\"limit\", String(limit))"))
}

@Test func missingOperationIdFallsBackToMethodAndPath() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /things/{thingId}:
        get:
          parameters:
            - name: thingId
              in: path
              required: true
              schema:
                type: integer
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("case getThingsThingId(thingId: Int)"))
    #expect(generated.contains("Endpoint(\"things/\\(String(thingId))\")"))
}

@Test func enumNameComesFromTitleAndIsOverridable() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths: {}
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("enum UnitFixtureEndpoint: RequestBuildable"))

    let overridden = try SwiftSpecGenerator(enumNameOverride: "CustomAPI").generate(yaml: yaml)
    #expect(overridden.contains("enum CustomAPI: RequestBuildable"))
}

@Test func headerParamsEmitTodoComment() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /things:
        get:
          operationId: listThings
          parameters:
            - name: X-Trace-Id
              in: header
              required: true
              schema:
                type: string
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("// TODO: header param X-Trace-Id not generated"))
    #expect(generated.contains("case listThings\n"))
}

@Test func pathItemLevelParametersAreMergedIntoOperations() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /users/{userId}/posts/{postId}:
        parameters:
          - name: userId
            in: path
            required: true
            schema:
              type: string
        get:
          operationId: getPost
          parameters:
            - name: postId
              in: path
              required: true
              schema:
                type: string
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("case getPost(userId: String, postId: String)"))
    #expect(generated.contains("Endpoint(\"users/\\(userId)/posts/\\(postId)\")"))
    #expect(!generated.contains("{userId}"))
}

@Test func operationLevelParameterOverridesPathItemLevelByNameAndLocation() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /things/{thingId}:
        parameters:
          - name: thingId
            in: path
            required: true
            schema:
              type: string
        get:
          operationId: showThing
          parameters:
            - name: thingId
              in: path
              required: true
              schema:
                type: integer
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("case showThing(thingId: Int)"))
    #expect(generated.contains("Endpoint(\"things/\\(String(thingId))\")"))
}

@Test func arrayQueryParamEmitsOneQueryPerElement() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /pets:
        get:
          operationId: findPets
          parameters:
            - name: tags
              in: query
              required: false
              schema:
                type: array
                items:
                  type: string
            - name: ids
              in: query
              required: true
              schema:
                type: array
                items:
                  type: integer
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("case findPets(tags: [String]?, ids: [Int])"))
    #expect(generated.contains("if let tags {"))
    #expect(generated.contains("for item in tags {"))
    #expect(generated.contains("Query(\"tags\", item)"))
    #expect(generated.contains("for item in ids {"))
    #expect(generated.contains("Query(\"ids\", String(item))"))
    #expect(!generated.contains("String(tags)"))
    #expect(!generated.contains("String(ids)"))
}

@Test func arrayPathParamIsJoinedWithCommas() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /groups/{ids}:
        get:
          operationId: getGroups
          parameters:
            - name: ids
              in: path
              required: true
              schema:
                type: array
                items:
                  type: integer
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("case getGroups(ids: [Int])"))
    #expect(generated.contains("Endpoint(\"groups/\\(ids.map { String($0) }.joined(separator: \",\"))\")"))
}

@Test func schemaNamesAreSanitizedToSwiftIdentifiers() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /things:
        post:
          operationId: makeThing
          requestBody:
            content:
              application/json:
                schema:
                  $ref: "#/components/schemas/thing-request"
    components:
      schemas:
        thing-request:
          type: object
        Thing.List:
          type: array
          items:
            $ref: "#/components/schemas/thing-request"
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("struct ThingRequest: Codable {}"))
    #expect(generated.contains("typealias ThingList = [ThingRequest]"))
    #expect(generated.contains("case makeThing(body: ThingRequest)"))
    #expect(!generated.contains("thing-request"))
    #expect(!generated.contains("Thing.List"))
}

@Test func stdlibCollidingSchemaNamesAreRenamed() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths: {}
    components:
      schemas:
        Error:
          type: object
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("struct APIError: Codable {}"))
    #expect(!generated.contains("struct Error"))
}

@Test func emptyPathsGeneratesPlaceholderBodyInsteadOfEmptySwitch() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths: {}
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(!generated.contains("switch self"))
    #expect(generated.contains("Method.GET"))
}

@Test func invalidYAMLThrows() {
    #expect(throws: GeneratorError.self) {
        try SwiftSpecGenerator().generate(yaml: "paths: [unclosed")
    }
    #expect(throws: GeneratorError.notAnOpenAPIDocument) {
        try SwiftSpecGenerator().generate(yaml: "- just\n- a\n- list")
    }
}
