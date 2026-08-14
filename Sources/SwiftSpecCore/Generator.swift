import Foundation
import Yams

/// Errors thrown by ``SwiftSpecGenerator``.
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
public struct SwiftSpecGenerator {
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
        let enumName = enumNameOverride ?? pascalIdentifier(title) + "Endpoint"

        var baseURL: String?
        if let servers = anyArray(document["servers"]),
           let first = anyDict(servers.first),
           let url = first["url"] as? String {
            baseURL = url
        }

        let componentParameters = anyDict(anyDict(document["components"])?["parameters"]) ?? [:]
        let documentSecurity = anyArray(document["security"])
        var models = collectSchemaModels(from: document)
        let operations = collectOperations(
            from: document,
            componentParameters: componentParameters,
            documentSecurity: documentSecurity,
            inlineBodyModels: &models
        )

        return render(
            enumName: enumName,
            baseURL: baseURL,
            models: models.sorted { $0.name < $1.name },
            operations: operations
        )
    }
}

// MARK: - Intermediate representation

struct Model {
    enum Kind {
        case structStub
        case arrayAlias(element: String)
        case scalarAlias(type: String)
    }

    var name: String
    var kind: Kind
}

struct Parameter {
    var rawName: String
    var swiftName: String
    var type: String
    var isOptional: Bool
    var location: String // "path" | "query" | "header" | "cookie"
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
}

// MARK: - Walking the document

extension SwiftSpecGenerator {
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
                return Model(name: modelTypeName(name), kind: .scalarAlias(type: swiftType(for: schema)))
            default:
                return Model(name: modelTypeName(name), kind: .structStub)
            }
        }
    }

    func collectOperations(
        from document: [String: Any],
        componentParameters: [String: Any],
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
                    documentSecurity: documentSecurity,
                    inlineBodyModels: &inlineBodyModels
                ) else { continue }
                operations.append(made)
            }
        }
        return operations
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
            parameters.append(Parameter(
                rawName: rawName,
                swiftName: camelIdentifier(rawName),
                type: swiftType(for: anyDict(parameter["schema"])),
                isOptional: !required,
                location: location
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
                let stubName = pascalIdentifier(caseName) + "Body"
                inlineBodyModels.append(Model(name: stubName, kind: .structStub))
                bodyType = stubName
            }
        }

        return Operation(
            caseName: caseName,
            method: method.uppercased(),
            path: path,
            parameters: parameters,
            bodyType: bodyType,
            securitySchemes: schemes
        )
    }
}

// MARK: - Rendering

extension SwiftSpecGenerator {
    func render(enumName: String, baseURL: String?, models: [Model], operations: [Operation]) -> String {
        var output = "// Generated by swift-spec. Do not edit.\n"
        if !excludedSchemes.isEmpty {
            output += "// Client-only: operations requiring \(excludedSchemes.sorted().joined(separator: ", ")) are not generated.\n"
        }
        output += "\nimport DeclarativeRequests\nimport Foundation\n"

        if !models.isEmpty {
            output += "\n// MARK: - Model stubs\n"
            for model in models {
                switch model.kind {
                case .structStub:
                    output += "struct \(model.name): Codable {}\n"
                case let .arrayAlias(element):
                    output += "typealias \(model.name) = [\(element)]\n"
                case let .scalarAlias(type):
                    output += "typealias \(model.name) = \(type)\n"
                }
            }
        }

        output += "\n// MARK: - Endpoints\n"
        output += "enum \(enumName): RequestBuildable {\n"
        for operation in operations {
            output += "    case \(operation.caseName)\(caseAssociatedValues(operation))\n"
        }
        if !operations.isEmpty {
            output += "\n"
        }
        if let baseURL {
            if baseURL.contains("{") {
                // A templated server URL (OpenAPI server variables) is not a
                // resolvable URL — record it, let the caller supply the base.
                output += "    /// Server URL is templated — supply a resolved base URL: `\(baseURL)`\n\n"
            } else {
                output += "    static let defaultBaseURL = URL(string: \"\(baseURL)\")\n\n"
            }
        }
        output += renderSecurity(operations)
        if operations.isEmpty {
            // A result-builder-transformed `switch self {}` with zero cases
            // does not compile, so emit a placeholder body instead. The enum
            // has no cases, so this body can never actually run.
            output += "    @RequestBuilder var body: some RequestBuildable {\n"
            output += "        // Spec contains no operations.\n"
            output += "        Method.GET\n"
            output += "    }\n"
        } else {
            output += "    @RequestBuilder var body: some RequestBuildable {\n"
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

    /// Renders `securitySchemes` and the README-style `needsAuth` per case.
    /// Omitted entirely when no operation declares a security requirement.
    func renderSecurity(_ operations: [Operation]) -> String {
        guard operations.contains(where: { !$0.securitySchemes.isEmpty }) else { return "" }

        func setLiteral(_ schemes: [String]) -> String {
            "[" + schemes.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
        }

        var output = "    /// Security scheme names the spec requires for this endpoint\n"
        output += "    /// (OR-alternatives flattened into one set).\n"
        output += "    var securitySchemes: Set<String> {\n"

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
            output += "        \(setLiteral(groups[0].schemes))\n"
        } else {
            output += "        switch self {\n"
            for group in groups {
                let patterns = group.caseNames.map { ".\($0)" }
                // Chunk long multi-pattern lines to keep them readable.
                for (index, chunk) in patterns.chunks(of: 5).enumerated() {
                    let prefix = index == 0 ? "        case " : "            "
                    let isLast = (index + 1) * 5 >= patterns.count
                    output += prefix + chunk.joined(separator: ", ") + (isLast ? ":\n" : ",\n")
                }
                output += "            \(setLiteral(group.schemes))\n"
            }
            output += "        }\n"
        }
        output += "    }\n\n"

        output += "    /// Whether the spec declares a security requirement for this endpoint.\n"
        output += "    var needsAuth: Bool {\n"
        output += "        !securitySchemes.isEmpty\n"
        output += "    }\n\n"

        // One `needs<Scheme>` flag per scheme the spec actually uses, so
        // wiring layers gate on a named fact instead of a string lookup.
        let allSchemes = Set(operations.flatMap(\.securitySchemes)).sorted()
        for scheme in allSchemes {
            output += "    /// Whether the spec requires the `\(scheme)` scheme for this endpoint.\n"
            output += "    var needs\(pascalIdentifier(scheme)): Bool {\n"
            output += "        securitySchemes.contains(\"\(scheme)\")\n"
            output += "    }\n\n"
        }
        return output
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
            let interpolation: String = if parameter.type == "String" {
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
        let value = parameter.type == "String"
            ? parameter.swiftName
            : "String(\(parameter.swiftName))"
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
