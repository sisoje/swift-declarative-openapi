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

// MARK: - Component parameter refs

@Test func parameterRefsResolveToComponentDefinitions() throws {
    let yaml = """
    openapi: "3.1.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /things/{thingId}:
        get:
          operationId: getThing
          parameters:
            - $ref: "#/components/parameters/ThingId"
            - $ref: "#/components/parameters/Verbose"
    components:
      parameters:
        ThingId:
          name: thingId
          in: path
          required: true
          schema:
            type: string
        Verbose:
          name: verbose
          in: query
          schema:
            type: boolean
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("case getThing(thingId: String, verbose: Bool?)"))
    #expect(generated.contains("Endpoint(\"things/\\(thingId)\")"))
    #expect(generated.contains("Query(\"verbose\", String(verbose))"))
}

@Test func unresolvableParameterRefIsDropped() throws {
    let yaml = """
    openapi: "3.1.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /things:
        get:
          operationId: listThings
          parameters:
            - $ref: "#/components/parameters/Missing"
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("case listThings\n"))
}

// MARK: - Scalar schema aliases

@Test func scalarSchemasBecomeTypealiases() throws {
    let yaml = """
    openapi: "3.1.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths: {}
    components:
      schemas:
        Email:
          type: string
        Count:
          type: integer
        Price:
          type: number
        Image:
          type: string
          format: binary
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("typealias Email = String"))
    #expect(generated.contains("typealias Count = Int"))
    #expect(generated.contains("typealias Price = Double"))
    #expect(generated.contains("typealias Image = Data"))
}

// MARK: - Server URL

@Test func templatedServerURLEmitsCommentInsteadOfConstant() throws {
    let yaml = """
    openapi: "3.0.3"
    info:
      title: Unit Fixture
      version: 1.0.0
    servers:
      - url: "https://{tenant}.example.com/v1"
    paths:
      /things:
        get:
          operationId: listThings
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(!generated.contains("defaultBaseURL"))
    #expect(generated.contains("/// Server URL is templated — supply a resolved base URL: `https://{tenant}.example.com/v1`"))
}

// MARK: - Security

@Test func operationSecurityOverridesDocumentDefault() throws {
    let yaml = """
    openapi: "3.0.3"
    info:
      title: Unit Fixture
      version: 1.0.0
    security:
      - DefaultAuth: []
    paths:
      /open:
        get:
          operationId: openThing
          security: []
      /locked:
        get:
          operationId: lockedThing
          security:
            - SpecialAuth: []
              OtherAuth: []
      /inherited:
        get:
          operationId: inheritedThing
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("var securitySchemes: Set<String>"))
    #expect(generated.contains("var needsDefaultAuth: Bool"))
    #expect(generated.contains("var needsSpecialAuth: Bool"))
    #expect(!generated.contains("var needsAuth: Bool"))
    #expect(generated.contains("case .openThing:\n            []"))
    #expect(generated.contains("case .lockedThing:\n            [\"OtherAuth\", \"SpecialAuth\"]"))
    #expect(generated.contains("case .inheritedThing:\n            [\"DefaultAuth\"]"))
}

@Test func noSecurityAnywhereOmitsSecurityProperties() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /things:
        get:
          operationId: listThings
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(!generated.contains("securitySchemes"))
    #expect(!generated.contains("needsAuth"))
}

@Test func excludedSchemeDropsOperationsRequiringIt() throws {
    let yaml = """
    openapi: "3.0.3"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /public:
        get:
          operationId: publicThing
      /admin:
        get:
          operationId: adminThing
          security:
            - AdminAuth: []
          requestBody:
            content:
              application/json:
                schema:
                  type: object
    """
    let generated = try SwiftSpecGenerator(excludedSchemes: ["AdminAuth"]).generate(yaml: yaml)
    #expect(generated.contains("case publicThing"))
    #expect(!generated.contains("adminThing"))
    #expect(!generated.contains("AdminThingBody"))
    #expect(generated.contains("// Client-only: operations requiring AdminAuth are not generated."))
}

// MARK: - Full models

@Test func fullModelsEmitRealProperties() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths: {}
    components:
      schemas:
        Thing:
          type: object
          required:
            - id
          properties:
            id:
              type: integer
            display_name:
              type: string
            tags:
              type: array
              items:
                type: string
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("struct Thing: Codable {"))
    #expect(generated.contains("var id: Int\n"))
    #expect(generated.contains("var displayName: String? = nil"))
    #expect(generated.contains("var tags: [String]? = nil"))
    #expect(generated.contains("case displayName = \"display_name\""))
    #expect(generated.contains("case id\n"))
}

@Test func fullModelsFlattenAllOf() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths: {}
    components:
      schemas:
        Base:
          type: object
          required:
            - id
          properties:
            id:
              type: string
        Extended:
          allOf:
            - $ref: "#/components/schemas/Base"
            - type: object
              required:
                - note
              properties:
                note:
                  type: string
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("struct Extended: Codable {\n    var id: String\n    var note: String\n}"))
}


// MARK: - String enums

@Test func enumParametersGenerateNestedEnums() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /token:
        post:
          operationId: issueToken
          parameters:
            - name: grant_type
              in: query
              required: true
              schema:
                type: string
                enum:
                  - password
                  - refresh_token
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("enum GrantType: String, Codable {"))
    #expect(generated.contains("case refreshToken = \"refresh_token\""))
    #expect(generated.contains("case issueToken(grantType: GrantType)"))
    #expect(generated.contains("Query(\"grant_type\", grantType.rawValue)"))
}

@Test func enumSchemasGenerateStringEnums() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths: {}
    components:
      schemas:
        Kind:
          type: string
          enum:
            - big-one
            - small
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("enum Kind: String, Codable {"))
    #expect(generated.contains("case bigOne = \"big-one\""))
    #expect(generated.contains("case small\n"))
}

@Test func conflictingEnumParameterNamesFallBackToString() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths:
      /a:
        get:
          operationId: getA
          parameters:
            - name: mode
              in: query
              schema:
                type: string
                enum: [x, y]
      /b:
        get:
          operationId: getB
          parameters:
            - name: mode
              in: query
              schema:
                type: string
                enum: [p, q]
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("case getA(mode: Mode?)"))
    #expect(generated.contains("case getB(mode: String?)"))
}

@Test func inlinePropertyEnumsGenerateNestedEnums() throws {
    let yaml = """
    openapi: "3.0.0"
    info:
      title: Unit Fixture
      version: 1.0.0
    paths: {}
    components:
      schemas:
        Video:
          type: object
          properties:
            quality:
              type: string
              enum:
                - 1080p
                - 720p
            codec:
              type: string
    """
    let generated = try SwiftSpecGenerator().generate(yaml: yaml)
    #expect(generated.contains("    enum Quality: String, Codable {"))
    #expect(generated.contains("case _1080p = \"1080p\""))
    #expect(generated.contains("var quality: Quality? = nil"))
    #expect(generated.contains("var codec: String? = nil"))
}
