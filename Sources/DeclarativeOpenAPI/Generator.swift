import Foundation
import Yams

/// Errors thrown by ``SpecGenerator``.
public enum GeneratorError: Swift.Error, CustomStringConvertible, Equatable {
    case invalidYAML(String)
    case notAnOpenAPIDocument

    public var description: String {
        switch self {
        case let .invalidYAML(detail): "invalid YAML: \(detail)"
        case .notAnOpenAPIDocument: "input is not an OpenAPI document (expected a top-level mapping)"
        }
    }
}

/// Generates a single Swift source file from an OpenAPI 3.x YAML document.
///
/// The output models every operation as one enum conforming to the
/// DeclarativeRequests `RequestBuildable` protocol, plus empty model stubs
/// for every entry in `components.schemas`.
public struct SpecGenerator {
    public var enumNameOverride: String?
    /// Operations whose effective security requires any of these schemes are
    /// not generated — e.g. exclude a server-only admin scheme to keep the
    /// output client-only.
    public var excludedSchemes: Set<String>

    public init(enumNameOverride: String? = nil, excludedSchemes: Set<String> = []) {
        self.enumNameOverride = enumNameOverride
        self.excludedSchemes = excludedSchemes
    }

    public func generate(yaml: String) throws -> String {
        let root: Any?
        do {
            root = try Yams.load(yaml: yaml)
        } catch {
            throw GeneratorError.invalidYAML(String(describing: error))
        }
        guard let document = anyDict(root) else {
            throw GeneratorError.notAnOpenAPIDocument
        }

        let info = anyDict(document["info"])
        let title = (info?["title"] as? String) ?? "API"
        let enumName = enumNameOverride ?? pascalIdentifier(title)

        var baseURL: String?
        if let servers = anyArray(document["servers"]),
           let first = anyDict(servers.first),
           let url = first["url"] as? String {
            baseURL = url
        }

        let componentParameters = anyDict(anyDict(document["components"])?["parameters"]) ?? [:]
        let componentSchemas = anyDict(anyDict(document["components"])?["schemas"]) ?? [:]
        let securitySchemeDefinitions = anyDict(anyDict(document["components"])?["securitySchemes"]) ?? [:]
        let documentSecurity = anyArray(document["security"])
        var models = collectSchemaModels(from: document)
        var operations = collectOperations(
            from: document,
            componentParameters: componentParameters,
            componentSchemas: componentSchemas,
            documentSecurity: documentSecurity,
            inlineBodyModels: &models
        )
        let parameterEnums = resolveParameterEnums(&operations)

        return render(
            enumName: enumName,
            baseURL: baseURL,
            models: models.sorted { $0.name < $1.name },
            operations: operations,
            parameterEnums: parameterEnums,
            securitySchemeDefinitions: securitySchemeDefinitions
        )
    }
}

// MARK: - Intermediate representation

struct Model {
    enum Kind {
        case structModel(properties: [ModelProperty])
        case arrayAlias(element: String)
        case scalarAlias(type: String)
        case stringEnum(cases: [String])
    }

    var name: String
    var kind: Kind
}

struct ModelProperty {
    var rawName: String
    var swiftName: String
    var type: String
    var isOptional: Bool
    /// Allowed values when the property schema is a string enum; the struct
    /// then carries a nested `enum <Type>: String` and the property uses it.
    var enumCases: [String]?
}

struct Parameter {
    var rawName: String
    var swiftName: String
    var type: String
    var isOptional: Bool
    var location: String // "path" | "query" | "header" | "cookie"
    /// Allowed values when the schema is a string enum; the parameter then
    /// gets a nested `enum <Type>: String` and renders via `.rawValue`.
    var enumCases: [String]?
}

struct Operation {
    var caseName: String
    var method: String // uppercased HTTP method
    var path: String
    var parameters: [Parameter]
    var bodyType: String?
    /// Security scheme names the spec requires for this operation, sorted.
    /// Operation-level `security` overrides the document default; the
    /// requirement objects' OR-alternatives are flattened into one set.
    var securitySchemes: [String]
    /// Status codes the spec declares below 400 for this operation, sorted —
    /// the operation's expected (non-error) responses. Empty when the spec
    /// declares none (evaluation then falls back to the 2xx range).
    var successStatuses: [Int]
}

// MARK: - Walking the document

extension SpecGenerator {
    /// Methods emitted in this fixed order within each path.
    static let methodOrder = ["get", "post", "put", "patch", "delete", "head", "options", "trace"]

    func collectSchemaModels(from document: [String: Any]) -> [Model] {
        guard let components = anyDict(document["components"]),
              let schemas = anyDict(components["schemas"]) else { return [] }
        return schemas.keys.map { name in
            let schema = anyDict(schemas[name])
            switch schema?["type"] as? String {
            case "array":
                return Model(
                    name: modelTypeName(name),
                    kind: .arrayAlias(element: swiftType(for: anyDict(schema?["items"])))
                )
            case "string", "integer", "number", "boolean":
                if let values = anyArray(schema?["enum"])?.compactMap({ $0 as? String }), !values.isEmpty {
                    return Model(name: modelTypeName(name), kind: .stringEnum(cases: values))
                }
                return Model(name: modelTypeName(name), kind: .scalarAlias(type: swiftType(for: schema)))
            default:
                return Model(
                    name: modelTypeName(name),
                    kind: .structModel(properties: collectProperties(of: schema ?? [:], in: schemas))
                )
            }
        }
    }

    /// Real properties from `properties`/`required`, with `allOf` branches
    /// ($refs resolved against `components.schemas`) flattened in.
    func collectProperties(of schema: [String: Any], in schemas: [String: Any]) -> [ModelProperty] {
        var required = Set<String>()
        var properties: [String: [String: Any]] = [:]

        func absorb(_ schema: [String: Any]) {
            for branch in (anyArray(schema["allOf"]) ?? []).compactMap(anyDict) {
                if let ref = branch["$ref"] as? String,
                   ref.hasPrefix("#/components/schemas/"),
                   let name = ref.split(separator: "/").last,
                   let resolved = anyDict(schemas[String(name)]) {
                    absorb(resolved)
                } else {
                    absorb(branch)
                }
            }
            for (name, property) in anyDict(schema["properties"]) ?? [:] {
                properties[name] = anyDict(property) ?? [:]
            }
            required.formUnion((anyArray(schema["required"]) ?? []).compactMap { $0 as? String })
        }
        absorb(schema)

        return properties.keys.sorted().map { rawName in
            let propertySchema = properties[rawName]
            var type = swiftType(for: propertySchema)
            var enumCases: [String]?
            if propertySchema?["type"] as? String == "string",
               let values = anyArray(propertySchema?["enum"])?.compactMap({ $0 as? String }),
               !values.isEmpty {
                enumCases = values
                type = modelTypeName(rawName)
            }
            return ModelProperty(
                rawName: rawName,
                swiftName: propertyName(rawName),
                type: type,
                isOptional: !required.contains(rawName),
                enumCases: enumCases
            )
        }
    }

    func collectOperations(
        from document: [String: Any],
        componentParameters: [String: Any],
        componentSchemas: [String: Any],
        documentSecurity: [Any]?,
        inlineBodyModels: inout [Model]
    ) -> [Operation] {
        guard let paths = anyDict(document["paths"]) else { return [] }
        var operations: [Operation] = []
        for path in paths.keys.sorted() {
            guard let pathItem = anyDict(paths[path]) else { continue }
            let pathItemParameters = (anyArray(pathItem["parameters"]) ?? [])
                .compactMap(anyDict)
                .compactMap { resolveParameter($0, componentParameters: componentParameters) }
            for method in Self.methodOrder {
                guard let operation = anyDict(pathItem[method]) else { continue }
                guard let made = makeOperation(
                    method: method,
                    path: path,
                    operation: operation,
                    pathItemParameters: pathItemParameters,
                    componentParameters: componentParameters,
                    componentSchemas: componentSchemas,
                    documentSecurity: documentSecurity,
                    inlineBodyModels: &inlineBodyModels
                ) else { continue }
                operations.append(made)
            }
        }
        return operations
    }

    /// Collects one nested enum per distinct enum-typed parameter name
    /// (first occurrence wins). A later parameter with the same name but a
    /// different value set falls back to `String` — one type name can't
    /// honestly carry two contracts.
    func resolveParameterEnums(_ operations: inout [Operation]) -> [(name: String, cases: [String])] {
        var enums: [(name: String, cases: [String])] = []
        for operationIndex in operations.indices {
            for parameterIndex in operations[operationIndex].parameters.indices {
                guard let cases = operations[operationIndex].parameters[parameterIndex].enumCases else { continue }
                let name = operations[operationIndex].parameters[parameterIndex].type
                if let existing = enums.first(where: { $0.name == name }) {
                    if existing.cases != cases {
                        operations[operationIndex].parameters[parameterIndex].type = "String"
                        operations[operationIndex].parameters[parameterIndex].enumCases = nil
                    }
                } else {
                    enums.append((name, cases))
                }
            }
        }
        return enums
    }

    /// Resolves a `$ref: "#/components/parameters/Name"` entry to its
    /// component definition; non-ref entries pass through, unresolvable
    /// refs are dropped.
    func resolveParameter(_ parameter: [String: Any], componentParameters: [String: Any]) -> [String: Any]? {
        guard let ref = parameter["$ref"] as? String else { return parameter }
        guard let name = ref.split(separator: "/").last,
              ref.hasPrefix("#/components/parameters/") else { return nil }
        return anyDict(componentParameters[String(name)])
    }

    func makeOperation(
        method: String,
        path: String,
        operation: [String: Any],
        pathItemParameters: [[String: Any]],
        componentParameters: [String: Any],
        componentSchemas: [String: Any],
        documentSecurity: [Any]?,
        inlineBodyModels: inout [Model]
    ) -> Operation? {
        // An operation-level `security:` (even an empty one, which marks the
        // operation public) overrides the document default. Resolve it first:
        // excluded operations must not register inline body stubs either.
        let effectiveSecurity = anyArray(operation["security"]) ?? documentSecurity ?? []
        let schemes = Set(effectiveSecurity.compactMap(anyDict).flatMap(\.keys)).sorted()
        guard excludedSchemes.isDisjoint(with: schemes) else { return nil }

        let caseName: String = if let operationId = operation["operationId"] as? String {
            camelIdentifier(operationId)
        } else {
            fallbackCaseName(method: method, path: path)
        }

        // Path-item-level parameters apply to every operation under the path;
        // operation-level entries override them by (name, in).
        var rawParameters = pathItemParameters
        for parameter in (anyArray(operation["parameters"]) ?? []).compactMap(anyDict)
            .compactMap({ resolveParameter($0, componentParameters: componentParameters) }) {
            if let index = rawParameters.firstIndex(where: {
                $0["name"] as? String == parameter["name"] as? String
                    && $0["in"] as? String == parameter["in"] as? String
            }) {
                rawParameters[index] = parameter
            } else {
                rawParameters.append(parameter)
            }
        }

        var parameters: [Parameter] = []
        for parameter in rawParameters {
            guard let rawName = parameter["name"] as? String,
                  let location = parameter["in"] as? String else { continue }
            let required = location == "path" || (parameter["required"] as? Bool ?? false)
            let schema = anyDict(parameter["schema"])
            var type = swiftType(for: schema)
            var enumCases: [String]?
            if schema?["type"] as? String == "string",
               let values = anyArray(schema?["enum"])?.compactMap({ $0 as? String }),
               !values.isEmpty {
                enumCases = values
                // modelTypeName also guards names Swift forbids or shadows
                // (a nested `enum Type` conflicts with `.Type` metatypes).
                type = modelTypeName(rawName)
            }
            parameters.append(Parameter(
                rawName: rawName,
                swiftName: camelIdentifier(rawName),
                type: type,
                isOptional: !required,
                location: location,
                enumCases: enumCases
            ))
        }

        var bodyType: String?
        if let requestBody = anyDict(operation["requestBody"]),
           let content = anyDict(requestBody["content"]),
           let json = anyDict(content["application/json"]),
           let schema = anyDict(json["schema"]) {
            if let ref = schema["$ref"] as? String {
                bodyType = refTypeName(ref)
            } else {
                let bodyName = pascalIdentifier(caseName) + "Body"
                inlineBodyModels.append(Model(
                    name: bodyName,
                    kind: .structModel(properties: collectProperties(of: schema, in: componentSchemas))
                ))
                bodyType = bodyName
            }
        }

        // Declared statuses below 400 are the operation's expected responses
        // ("default" and error statuses are not success shapes).
        let successStatuses = (anyDict(operation["responses"]) ?? [:]).keys
            .compactMap { Int($0) }
            .filter { $0 < 400 }
            .sorted()

        return Operation(
            caseName: caseName,
            method: method.uppercased(),
            path: path,
            parameters: parameters,
            bodyType: bodyType,
            securitySchemes: schemes,
            successStatuses: successStatuses
        )
    }
}

// MARK: - Rendering

extension SpecGenerator {
    func render(
        enumName: String,
        baseURL: String?,
        models: [Model],
        operations: [Operation],
        parameterEnums: [(name: String, cases: [String])],
        securitySchemeDefinitions: [String: Any]
    ) -> String {
        var output = "// Generated by declarative-openapi. Do not edit.\n"
        if !excludedSchemes.isEmpty {
            output += "// Client-only: operations requiring \(excludedSchemes.sorted().joined(separator: ", ")) are not generated.\n"
        }
        output += "\nimport DeclarativeRequests\nimport Foundation\n\n"

        // "Whole" would be a lie when operations are excluded — say which slice this is.
        output += excludedSchemes.isEmpty
            ? "// The whole backend in one closed type — sections mirror the OpenAPI document.\n"
            : "// The client-facing slice of the backend in one closed type — sections mirror the OpenAPI document.\n"
        output += "enum \(enumName) {\n"

        if !models.isEmpty {
            output += "    // MARK: - Schemas (components.schemas)\n\n"
            output += indented(models.map(renderModel).joined(separator: "\n"))
            output += "\n"
        }

        output += "    // MARK: - Operations (paths)\n\n"
        output += indented(renderOperationEnum(operations: operations, parameterEnums: parameterEnums))

        output += renderResponses(operations)
        output += renderSecurity(operations, definitions: securitySchemeDefinitions)

        if let baseURL {
            output += "\n"
            if baseURL.contains("{") {
                // A templated server URL (OpenAPI server variables) is not a
                // resolvable URL — record it, let the caller supply the base.
                output += "    /// Server URL is templated — supply a resolved base URL: `\(baseURL)`\n"
            } else {
                output += "    static let defaultBaseURL = URL(string: \"\(baseURL)\")\n"
            }
        }
        output += "}\n"
        return output
    }

    /// Prefixes every non-empty line with one indentation level.
    func indented(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "    " + $0 }
            .joined(separator: "\n")
    }

    /// The `Operation` section: each operation IS a block.
    func renderOperationEnum(
        operations: [Operation],
        parameterEnums: [(name: String, cases: [String])]
    ) -> String {
        var output = "// each operation IS a block\n"
        output += "enum Operation: RequestBuildable {\n"
        for parameterEnum in parameterEnums {
            output += renderStringEnum(parameterEnum.name, cases: parameterEnum.cases, indent: "    ")
            output += "\n"
        }
        for operation in operations {
            output += "    case \(operation.caseName)\(caseAssociatedValues(operation))\n"
        }
        if !operations.isEmpty {
            output += "\n"
        }
        if operations.isEmpty {
            // A result-builder-transformed `switch self {}` with zero cases
            // does not compile, so emit a placeholder body instead. The enum
            // has no cases, so this body can never actually run.
            output += "    var body: some RequestBuildable {\n"
            output += "        // Spec contains no operations.\n"
            output += "        Method.GET\n"
            output += "    }\n"
        } else {
            output += "    var body: some RequestBuildable {\n"
            output += "        switch self {\n"
            for operation in operations {
                output += renderSwitchCase(operation)
            }
            output += "        }\n"
            output += "    }\n"
        }
        output += "}\n"
        return output
    }

    func renderStringEnum(_ name: String, cases: [String], indent: String) -> String {
        var output = "\(indent)enum \(name): String, Codable {\n"
        for value in cases {
            var caseName = propertyName(value)
            if caseName.first?.isNumber == true {
                // Swift identifiers can't start with a digit ("1080p").
                caseName = "_" + caseName
            }
            output += caseName == value
                ? "\(indent)    case \(value)\n"
                : "\(indent)    case \(caseName) = \"\(value)\"\n"
        }
        output += "\(indent)}\n"
        return output
    }

    func renderModel(_ model: Model) -> String {
        switch model.kind {
        case let .stringEnum(cases):
            return renderStringEnum(model.name, cases: cases, indent: "")
        case let .arrayAlias(element):
            return "typealias \(model.name) = [\(element)]\n"
        case let .scalarAlias(type):
            return "typealias \(model.name) = \(type)\n"
        case let .structModel(properties):
            guard !properties.isEmpty else { return "struct \(model.name): Codable {}\n" }
            var output = "struct \(model.name): Codable {\n"
            for property in properties {
                guard let cases = property.enumCases else { continue }
                output += renderStringEnum(property.type, cases: cases, indent: "    ")
                output += "\n"
            }
            for property in properties {
                output += "    var \(property.swiftName): \(property.type)\(property.isOptional ? "? = nil" : "")\n"
            }
            // CodingKeys only when a raw name isn't already a clean Swift name.
            if properties.contains(where: { $0.swiftName != $0.rawName }) {
                output += "\n    enum CodingKeys: String, CodingKey {\n"
                for property in properties {
                    output += property.swiftName == property.rawName
                        ? "        case \(property.swiftName)\n"
                        : "        case \(property.swiftName) = \"\(property.rawName)\"\n"
                }
                output += "    }\n"
            }
            output += "}\n"
            return output
        }
    }

    /// The `Responses` section: per-operation expected statuses from the
    /// spec's `responses:`, an `evaluate` gate over a transport result, and
    /// one lossless error — the next layer decodes the spec's error model
    /// from `data` when it needs it.
    func renderResponses(_ operations: [Operation]) -> String {
        guard !operations.isEmpty else { return "" }

        var output = "\n    // MARK: - Responses (responses)\n\n"
        output += "    /// One error, nothing lost: status, payload, and the raw response —\n"
        output += "    /// decode the spec's error model from `data` in the layer that needs it.\n"
        output += "    struct ResponseError: Error {\n"
        output += "        let operation: Operation\n"
        output += "        let status: Int\n"
        output += "        let data: Data\n"
        output += "        let response: HTTPURLResponse\n"
        output += "    }\n\n"
        output += "    enum Responses {\n"
        output += "        /// Statuses the spec declares below 400 for the operation.\n"
        output += "        static func successStatuses(_ operation: Operation) -> Set<Int> {\n"

        var groups: [(statuses: [Int], caseNames: [String])] = []
        for operation in operations {
            if let index = groups.firstIndex(where: { $0.statuses == operation.successStatuses }) {
                groups[index].caseNames.append(operation.caseName)
            } else {
                groups.append((operation.successStatuses, [operation.caseName]))
            }
        }

        func setLiteral(_ statuses: [Int]) -> String {
            "[" + statuses.map(String.init).joined(separator: ", ") + "]"
        }

        if groups.count == 1 {
            output += "            \(setLiteral(groups[0].statuses))\n"
        } else {
            output += "            switch operation {\n"
            for group in groups {
                let patterns = group.caseNames.map { ".\($0)" }
                for (index, chunk) in patterns.chunks(of: 5).enumerated() {
                    let prefix = index == 0 ? "            case " : "                "
                    let isLast = (index + 1) * 5 >= patterns.count
                    output += prefix + chunk.joined(separator: ", ") + (isLast ? ":\n" : ",\n")
                }
                output += "                \(setLiteral(group.statuses))\n"
            }
            output += "            }\n"
        }
        output += "        }\n\n"
        output += "        /// Gates a transport result through the spec: payload on an expected\n"
        output += "        /// status, `ResponseError` otherwise. Operations with no declared\n"
        output += "        /// success status fall back to the 2xx range.\n"
        output += "        static func evaluate(\n"
        output += "            _ operation: Operation,\n"
        output += "            _ output: (data: Data, response: HTTPURLResponse)\n"
        output += "        ) throws -> Data {\n"
        output += "            let declared = successStatuses(operation)\n"
        output += "            let status = output.response.statusCode\n"
        output += "            let expected = declared.isEmpty ? (200 ..< 300).contains(status) : declared.contains(status)\n"
        output += "            guard expected else {\n"
        output += "                throw ResponseError(operation: operation, status: status, data: output.data, response: output.response)\n"
        output += "            }\n"
        output += "            return output.data\n"
        output += "        }\n"
        output += "    }\n"
        return output
    }

    /// The `Security` section: a `schemes(_:)` gate over the flattened
    /// per-operation scheme sets, one `needs<Scheme>(_:)` gate per scheme,
    /// and one attachment factory per scheme derived from
    /// `components.securitySchemes` — the spec says *how* a credential
    /// attaches, so the factory is generated, not hand-written.
    /// Omitted entirely when no operation declares a security requirement.
    func renderSecurity(_ operations: [Operation], definitions: [String: Any]) -> String {
        guard operations.contains(where: { !$0.securitySchemes.isEmpty }) else { return "" }

        func setLiteral(_ schemes: [String]) -> String {
            "[" + schemes.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
        }

        var output = "\n    // MARK: - Security (securitySchemes)\n\n"
        output += "    enum Security {\n"
        output += "        /// Scheme names the spec requires for an operation\n"
        output += "        /// (OR-alternatives flattened into one set).\n"
        output += "        static func schemes(_ operation: Operation) -> Set<String> {\n"

        // Group cases sharing a scheme set, in first-occurrence order.
        var groups: [(schemes: [String], caseNames: [String])] = []
        for operation in operations {
            if let index = groups.firstIndex(where: { $0.schemes == operation.securitySchemes }) {
                groups[index].caseNames.append(operation.caseName)
            } else {
                groups.append((operation.securitySchemes, [operation.caseName]))
            }
        }

        if groups.count == 1 {
            output += "            \(setLiteral(groups[0].schemes))\n"
        } else {
            output += "            switch operation {\n"
            for group in groups {
                let patterns = group.caseNames.map { ".\($0)" }
                // Chunk long multi-pattern lines to keep them readable.
                for (index, chunk) in patterns.chunks(of: 5).enumerated() {
                    let prefix = index == 0 ? "            case " : "                "
                    let isLast = (index + 1) * 5 >= patterns.count
                    output += prefix + chunk.joined(separator: ", ") + (isLast ? ":\n" : ",\n")
                }
                output += "                \(setLiteral(group.schemes))\n"
            }
            output += "            }\n"
        }
        output += "        }\n"

        let allSchemes = Set(operations.flatMap(\.securitySchemes)).sorted()
        for scheme in allSchemes {
            output += "\n        /// Whether the spec requires `\(scheme)` for the operation.\n"
            output += "        static func needs\(pascalIdentifier(scheme))(_ operation: Operation) -> Bool {\n"
            output += "            schemes(operation).contains(\"\(scheme)\")\n"
            output += "        }\n"
        }

        for scheme in allSchemes {
            if let factory = attachmentFactory(scheme: scheme, definition: anyDict(definitions[scheme])) {
                output += "\n" + factory
            }
        }
        output += "    }\n"
        return output
    }

    /// One scheme = one factory, from the scheme's declared attachment
    /// mechanics. Unknown types (oauth2, openIdConnect) get no factory.
    func attachmentFactory(scheme: String, definition: [String: Any]?) -> String? {
        guard let definition else { return nil }
        let name = factoryName(scheme)
        switch (definition["type"] as? String, definition["scheme"] as? String) {
        case ("http", "bearer"):
            return """
                    static func \(name)(token: String) -> some RequestBuildable {
                        Authorization.bearer(token)
                    }

            """
        case ("http", "basic"):
            return """
                    static func \(name)(username: String, password: String) -> some RequestBuildable {
                        Authorization.basic(username: username, password: password)
                    }

            """
        case ("apiKey", _):
            guard let keyName = definition["name"] as? String else { return nil }
            switch definition["in"] as? String {
            case "header":
                return """
                        static func \(name)(_ value: String) -> some RequestBuildable {
                            Header.custom("\(keyName)").setValue(value)
                        }

                """
            case "query":
                return """
                        static func \(name)(_ value: String) -> some RequestBuildable {
                            Query("\(keyName)", value)
                        }

                """
            default:
                return nil
            }
        default:
            return "        // TODO: security scheme \(scheme) (type \(definition["type"] as? String ?? "?")) has no generated factory\n"
        }
    }

    func caseAssociatedValues(_ operation: Operation) -> String {
        var values: [String] = []
        for parameter in operation.parameters where parameter.location == "path" || parameter.location == "query" {
            values.append("\(parameter.swiftName): \(parameter.type)\(parameter.isOptional ? "?" : "")")
        }
        if let bodyType = operation.bodyType {
            values.append("body: \(bodyType)")
        }
        guard !values.isEmpty else { return "" }
        return "(\(values.joined(separator: ", ")))"
    }

    func renderSwitchCase(_ operation: Operation) -> String {
        var bindings: [String] = []
        for parameter in operation.parameters where parameter.location == "path" || parameter.location == "query" {
            bindings.append(parameter.swiftName)
        }
        if operation.bodyType != nil {
            bindings.append("body")
        }

        var output = if bindings.isEmpty {
            "        case .\(operation.caseName):\n"
        } else {
            "        case let .\(operation.caseName)(\(bindings.joined(separator: ", "))):\n"
        }

        output += "            Method.\(operation.method)\n"
        output += "            Endpoint(\"\(endpointPath(for: operation))\")\n"

        for parameter in operation.parameters {
            switch parameter.location {
            case "query":
                let statements = queryStatements(parameter)
                if parameter.isOptional {
                    output += "            if let \(parameter.swiftName) {\n"
                    output += statements.map { "                \($0)\n" }.joined()
                    output += "            }\n"
                } else {
                    output += statements.map { "            \($0)\n" }.joined()
                }
            case "header", "cookie":
                output += "            // TODO: \(parameter.location) param \(parameter.rawName) not generated\n"
            default:
                break
            }
        }

        if operation.bodyType != nil {
            output += "            RequestBody.json(body)\n"
        }
        return output
    }

    /// Interpolates path parameters and strips the leading slash so the
    /// emitted `Endpoint` joins cleanly onto a base URL.
    func endpointPath(for operation: Operation) -> String {
        var path = stripLeadingSlash(operation.path)
        for parameter in operation.parameters where parameter.location == "path" {
            let interpolation: String = if parameter.enumCases != nil {
                "\\(\(parameter.swiftName).rawValue)"
            } else if parameter.type == "String" {
                "\\(\(parameter.swiftName))"
            } else if parameter.type.hasPrefix("[") {
                // Array path params use OpenAPI's default (simple style):
                // comma-separated values.
                parameter.type == "[String]"
                    ? "\\(\(parameter.swiftName).joined(separator: \",\"))"
                    : "\\(\(parameter.swiftName).map { String($0) }.joined(separator: \",\"))"
            } else {
                "\\(String(\(parameter.swiftName)))"
            }
            path = path.replacingOccurrences(of: "{\(parameter.rawName)}", with: interpolation)
        }
        return path
    }

    /// Statement lines (unindented) that emit the `Query` block(s) for one
    /// query parameter. Array-typed params emit one `Query` per element via
    /// `for`-in (OpenAPI's default `form` + `explode: true` serialization);
    /// everything else emits a single stringified `Query`.
    func queryStatements(_ parameter: Parameter) -> [String] {
        if parameter.type.hasPrefix("[") {
            let element = parameter.type == "[String]" ? "item" : "String(item)"
            return [
                "for item in \(parameter.swiftName) {",
                "    Query(\"\(parameter.rawName)\", \(element))",
                "}",
            ]
        }
        let value = if parameter.enumCases != nil {
            "\(parameter.swiftName).rawValue"
        } else if parameter.type == "String" {
            parameter.swiftName
        } else {
            "String(\(parameter.swiftName))"
        }
        return ["Query(\"\(parameter.rawName)\", \(value))"]
    }
}

// MARK: - Naming and type mapping helpers

/// Splits on non-alphanumeric characters and joins with an uppercased first
/// letter per word; the very first letter is lowercased.
func camelIdentifier(_ string: String) -> String {
    let pascal = pascalIdentifier(string)
    guard let first = pascal.first else { return pascal }
    return first.lowercased() + pascal.dropFirst()
}

/// Splits on non-alphanumeric characters and joins with an uppercased first
/// letter per word.
func pascalIdentifier(_ string: String) -> String {
    let words = string.split { !$0.isLetter && !$0.isNumber }
    return words.map { word in
        guard let first = word.first else { return "" }
        return first.uppercased() + word.dropFirst()
    }.joined()
}

/// Case name used when an operation has no `operationId`:
/// lowercased method followed by the PascalCased path components.
func fallbackCaseName(method: String, path: String) -> String {
    method.lowercased() + path.split(separator: "/").map { pascalIdentifier(String($0)) }.joined()
}

/// Maps an OpenAPI schema to a Swift type name.
func swiftType(for schema: [String: Any]?) -> String {
    guard let schema else { return "String" }
    if let ref = schema["$ref"] as? String {
        return refTypeName(ref)
    }
    switch schema["type"] as? String {
    case "string": return schema["format"] as? String == "binary" ? "Data" : "String"
    case "integer": return "Int"
    case "number": return "Double"
    case "boolean": return "Bool"
    case "array": return "[\(swiftType(for: anyDict(schema["items"])))]"
    default: return "String"
    }
}

/// `#/components/schemas/Pet` -> `Pet`.
///
/// The raw name is sanitized through ``modelTypeName(_:)`` so references
/// always match the (sanitized) declaration site.
func refTypeName(_ ref: String) -> String {
    modelTypeName(ref.split(separator: "/").last.map(String.init) ?? ref)
}

/// Type names that would shadow ubiquitous standard-library types if a
/// generated model used them (e.g. a module-level `Error` shadows
/// `Swift.Error` for the whole module).
let stdlibCollidingTypeNames: Set<String> = [
    "Error", "Result", "Optional", "Never", "Any", "Self", "Type", "Protocol",
    "String", "Int", "Double", "Float", "Bool", "Character",
    "Array", "Dictionary", "Set", "Data", "Date", "URL", "UUID", "Decimal",
]

/// Sanitizes a raw OpenAPI component name to a valid Swift type name.
///
/// OpenAPI component keys may contain `-` and `.` (pattern
/// `^[a-zA-Z0-9.\-_]+$`), which are not valid in Swift identifiers, so the
/// name is PascalCased. Names that would shadow standard-library types are
/// prefixed with `API` (e.g. `Error` -> `APIError`).
func modelTypeName(_ raw: String) -> String {
    let name = pascalIdentifier(raw)
    return stdlibCollidingTypeNames.contains(name) ? "API" + name : name
}

/// Swift keywords a schema property name could collide with; escaped with backticks.
let swiftPropertyKeywords: Set<String> = [
    "as", "case", "class", "default", "enum", "extension", "false", "for", "func",
    "import", "in", "internal", "is", "nil", "operator", "private", "protocol",
    "public", "return", "self", "static", "struct", "true", "var", "where", "while",
]

/// Camel-cases a raw property name; keywords get backticks. When the result
/// differs from the raw name, the emitted struct carries `CodingKeys`.
func propertyName(_ raw: String) -> String {
    let name = camelIdentifier(raw)
    return swiftPropertyKeywords.contains(name) ? "`\(name)`" : name
}

/// Acronym-aware lower-camel for factory names: `APIKeyAuth` → `apiKeyAuth`,
/// `UserAuth` → `userAuth` (plain `camelIdentifier` would give `aPIKeyAuth`).
func factoryName(_ scheme: String) -> String {
    let pascal = pascalIdentifier(scheme)
    let characters = Array(pascal)
    var run = 0
    while run < characters.count, characters[run].isUppercase { run += 1 }
    if run == 0 { return pascal }
    // Keep the last uppercase of a multi-letter run — it starts the next word.
    let lowered = run == characters.count || run == 1 ? run : run - 1
    return pascal.prefix(lowered).lowercased() + pascal.dropFirst(lowered)
}

func stripLeadingSlash(_ path: String) -> String {
    path.hasPrefix("/") ? String(path.dropFirst()) : path
}

// MARK: - Loosely typed YAML access

func anyDict(_ any: Any?) -> [String: Any]? {
    if let dictionary = any as? [String: Any] { return dictionary }
    if let dictionary = any as? [AnyHashable: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            result[String(describing: key.base)] = value
        }
        return result
    }
    return nil
}

func anyArray(_ any: Any?) -> [Any]? {
    any as? [Any]
}

extension Array {
    func chunks(of size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
