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

/// Gates a transport result through the spec: payload on an expected status,
/// `ResponseError` otherwise (non-HTTP responses throw too). An empty
/// declared set falls back to the 2xx range.
public func evaluate<Operation>(
    _ operation: Operation,
    _ output: (data: Data, response: URLResponse),
    successStatuses: Set<Int>
) throws -> Data {
    guard let http = output.response as? HTTPURLResponse else {
        throw ResponseError(operation: operation, data: output.data, response: output.response)
    }
    let expected = successStatuses.isEmpty
        ? (200 ..< 300).contains(http.statusCode)
        : successStatuses.contains(http.statusCode)
    guard expected else {
        throw ResponseError(operation: operation, data: output.data, response: http)
    }
    return output.data
}
