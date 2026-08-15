import Foundation

/// The (Operation) → Data seam in wire vocabulary, composed once for
/// every backend — the only runtime type that speaks URLRequest/URLResponse.
/// Properties are the dependencies — request → transport → evaluate —
/// and `execute` is the output. Wrap it (retry, logging, caching) and
/// hand the result to `wired`: middleware is closure composition.
public struct NetworkExecution<Operation> {
    public let request: (Operation) throws -> URLRequest
    public let transport: (URLRequest) async throws -> (Data, URLResponse)
    public let successStatuses: (Operation) -> Set<Int>

    public init(
        request: @escaping (Operation) throws -> URLRequest,
        transport: @escaping (URLRequest) async throws -> (Data, URLResponse),
        successStatuses: @escaping (Operation) -> Set<Int>
    ) {
        self.request = request
        self.transport = transport
        self.successStatuses = successStatuses
    }

    public func execute(_ operation: Operation) async throws -> Data {
        try ResponseError.evaluate(try await transport(request(operation)), successStatuses: successStatuses(operation))
    }
}
