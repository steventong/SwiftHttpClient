import Foundation

public enum HTTPClientError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(code: Int)
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
