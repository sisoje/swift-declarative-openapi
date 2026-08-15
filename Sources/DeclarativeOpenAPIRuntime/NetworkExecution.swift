import Foundation

/// The (Operation) → Data seam in wire vocabulary, composed once for
/// every backend — the only runtime type that speaks URLRequest/URLResponse.
/// Properties are the dependencies — request → transport → evaluate —
/// and `execute` is the output. Wrap it (retry, logging, caching) and
/// hand the result to `wired`: middleware is closure composition.
public struct NetworkExecution<Operation> {
    public let request: (Operation) throws -> URLRequest
    public let transport: (URLRequest) async throws -> (Data, URLResponse)
    public let evaluate: (Operation, (data: Data, response: URLResponse)) throws -> Data

    public init(
        request: @escaping (Operation) throws -> URLRequest,
        transport: @escaping (URLRequest) async throws -> (Data, URLResponse),
        evaluate: @escaping (Operation, (data: Data, response: URLResponse)) throws -> Data
    ) {
        self.request = request
        self.transport = transport
        self.evaluate = evaluate
    }

    public func execute(_ operation: Operation) async throws -> Data {
        try evaluate(operation, try await transport(request(operation)))
    }
}
