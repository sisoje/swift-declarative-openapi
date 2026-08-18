import Foundation

/// The typed-closure mechanics, once for every backend: captures the
/// (Operation) → Data seam and a decoder choice, and turns case
/// constructors into typed client fields. Generated `Client.wired` tables
/// are pure facts over these four.
public struct ClientBuilder<Operation: Sendable>: Sendable {
    public let execute: @Sendable (Operation) async throws -> Data
    public let decoder: @Sendable (Operation) -> JSONDecoder

    public init(
        execute: @escaping @Sendable (Operation) async throws -> Data,
        decoder: @escaping @Sendable (Operation) -> JSONDecoder
    ) {
        self.execute = execute
        self.decoder = decoder
    }

    /// JSON response: decode into the spec-declared model.
    public func endpoint<each Input, Output: Decodable & SendableMetatype>(
        _ makeCase: @escaping @Sendable (repeat each Input) -> Operation,
        _ output: Output.Type
    ) -> @Sendable (repeat each Input) async throws -> Output {
        { (input: repeat each Input) in
            let operation = makeCase(repeat each input)
            let data = try await self.execute(operation)
            return try await self.decode(operation, data)
        }
    }

    /// Decoding runs off the caller's actor by contract (`@concurrent`,
    /// SE-0461), not by the current language default: a large payload never
    /// blocks the main actor, and stays off it even under
    /// `NonisolatedNonsendingByDefault`.
    @concurrent
    private func decode<Output: Decodable & SendableMetatype>(_ operation: Operation, _ data: Data) async throws -> Output {
        try decoder(operation).decode(Output.self, from: data)
    }

    /// Non-JSON content or undeclared shape: raw bytes.
    public func raw<each Input>(
        _ makeCase: @escaping @Sendable (repeat each Input) -> Operation
    ) -> @Sendable (repeat each Input) async throws -> Data {
        { (input: repeat each Input) in
            try await self.execute(makeCase(repeat each input))
        }
    }

    /// text/* content: raw UTF-8, never JSONDecoder.
    public func text<each Input>(
        _ makeCase: @escaping @Sendable (repeat each Input) -> Operation
    ) -> @Sendable (repeat each Input) async throws -> String {
        { (input: repeat each Input) in
            try String(decoding: await self.execute(makeCase(repeat each input)), as: UTF8.self)
        }
    }

    /// No content: evaluate, discard.
    public func fire<each Input>(
        _ makeCase: @escaping @Sendable (repeat each Input) -> Operation
    ) -> @Sendable (repeat each Input) async throws -> Void {
        { (input: repeat each Input) in
            _ = try await self.execute(makeCase(repeat each input))
        }
    }
}
