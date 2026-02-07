import Foundation

/// Errors exposed by `HTTPClient`.
public enum HTTPClientError: Error, LocalizedError, Sendable {
    /// Response cannot be cast to `HTTPURLResponse`.
    case invalidResponse
    /// Non-2xx HTTP status code.
    case httpStatus(code: Int)
    /// JSON decoding failed with underlying reason.
    case decodingFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response type"
        case let .httpStatus(code):
            return "Invalid http status code: \(code)"
        case let .decodingFailed(message):
            return "Failed to decode response: \(message)"
        }
    }
}
