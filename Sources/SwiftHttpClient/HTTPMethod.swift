import Foundation

/// Supported HTTP methods used by `HTTPClient`.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}
