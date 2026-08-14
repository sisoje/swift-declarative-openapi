import Foundation

/// One error, nothing lost: payload and the raw response — decode the spec's
/// error model from `data` in the layer that needs it. Universal across all
/// generated backends; each namespace aliases it to its own `Operation`.
public struct ResponseError<Operation>: Error {
    public let operation: Operation
    public let data: Data
    public let response: URLResponse

    /// Projection, not storage: nil when the transport didn't speak HTTP.
    public var status: Int? {
        (response as? HTTPURLResponse)?.statusCode
    }

    public init(operation: Operation, data: Data, response: URLResponse) {
        self.operation = operation
        self.data = data
        self.response = response
    }
}
