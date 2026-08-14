import Foundation

/// The typed-closure mechanics, once for every backend: captures the
/// (Operation) → Data seam and a decoder choice, and turns case
/// constructors into typed client fields. Generated `Client.wired` tables
/// are pure facts over these four.
public struct ClientBuilder<Operation> {
    public let execute: (Operation) async throws -> Data
    public let decoder: (Operation) -> JSONDecoder

    public init(
        execute: @escaping (Operation) async throws -> Data,
        decoder: @escaping (Operation) -> JSONDecoder
    ) {
        self.execute = execute
        self.decoder = decoder
    }

    /// JSON response: decode into the spec-declared model.
    public func endpoint<each Input, Output: Decodable>(
        _ makeCase: @escaping (repeat each Input) -> Operation,
        _ output: Output.Type
    ) -> (repeat each Input) async throws -> Output {
        { (input: repeat each Input) in
            let operation = makeCase(repeat each input)
            let data = try await self.execute(operation)
            return try self.decoder(operation).decode(Output.self, from: data)
        }
    }

    /// Non-JSON content or undeclared shape: raw bytes.
    public func raw<each Input>(
        _ makeCase: @escaping (repeat each Input) -> Operation
    ) -> (repeat each Input) async throws -> Data {
        { (input: repeat each Input) in
            try await self.execute(makeCase(repeat each input))
        }
    }

    /// text/* content: raw UTF-8, never JSONDecoder.
    public func text<each Input>(
        _ makeCase: @escaping (repeat each Input) -> Operation
    ) -> (repeat each Input) async throws -> String {
        { (input: repeat each Input) in
            try String(decoding: await self.execute(makeCase(repeat each input)), as: UTF8.self)
        }
    }

    /// No content: evaluate, discard.
    public func fire<each Input>(
        _ makeCase: @escaping (repeat each Input) -> Operation
    ) -> (repeat each Input) async throws -> Void {
        { (input: repeat each Input) in
            _ = try await self.execute(makeCase(repeat each input))
        }
    }
}
