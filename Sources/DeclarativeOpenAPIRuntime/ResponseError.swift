import Foundation

/// One error, nothing lost: payload and the raw response — decode the spec's
/// error model from `data` in the layer that needs it. Universal and
/// non-generic; the catching caller already knows which operation it ran.
public struct ResponseError: Error {
    public let data: Data
    public let response: URLResponse

    /// Projection, not storage: nil when the transport didn't speak HTTP.
    public var status: Int? {
        (response as? HTTPURLResponse)?.statusCode
    }

    public init(data: Data, response: URLResponse) {
        self.data = data
        self.response = response
    }
}

public enum Responses {
    /// Gates a transport result through the spec: payload on an expected
    /// status, `ResponseError` otherwise (non-HTTP responses throw too). An
    /// empty declared set falls back to the 2xx range.
    public static func evaluate(
        _ output: (data: Data, response: URLResponse),
        successStatuses: Set<Int>
    ) throws(ResponseError) -> Data {
        guard let http = output.response as? HTTPURLResponse else {
            throw ResponseError(data: output.data, response: output.response)
        }
        let expected = successStatuses.isEmpty
            ? (200 ..< 300).contains(http.statusCode)
            : successStatuses.contains(http.statusCode)
        guard expected else {
            throw ResponseError(data: output.data, response: http)
        }
        return output.data
    }
}
