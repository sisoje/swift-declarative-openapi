import Foundation

/// The (Operation) → Data seam in wire vocabulary, composed once for
/// every backend — the only runtime type that speaks URLRequest/URLResponse.
/// Properties are the dependencies — request → transport → evaluate —
/// and `execute` is the output. Wrap it (retry, logging, caching) and
/// hand the result to `wired`: middleware is closure composition.
public struct NetworkExecution<Operation: Sendable>: Sendable {
    public let request: @Sendable (Operation) throws -> URLRequest
    public let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public let successStatuses: @Sendable (Operation) -> Set<Int>

    public init(
        request: @escaping @Sendable (Operation) throws -> URLRequest,
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
        successStatuses: @escaping @Sendable (Operation) -> Set<Int>
    ) {
        self.request = request
        self.transport = transport
        self.successStatuses = successStatuses
    }

    /// The whole seam is wire work — request building (including JSON body
    /// encoding), transport, status gate — with no actor state, so it runs
    /// off the caller's actor by contract (`@concurrent`, SE-0461): a
    /// main-actor caller never encodes a body or composes a URL on the UI
    /// thread, even under `NonisolatedNonsendingByDefault`.
    @concurrent
    public func execute(_ operation: Operation) async throws -> Data {
        try ResponseError.evaluate(try await transport(request(operation)), successStatuses: successStatuses(operation))
    }
}
