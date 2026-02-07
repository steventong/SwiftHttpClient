import Foundation

/// A lightweight async HTTP client with typed decoding helpers.
public final class HTTPClient {
    private let session: URLSession

    /// Creates a client with request timeout.
    /// - Parameter timeout: Timeout for each request in seconds.
    public init(timeout: TimeInterval = 10) {
        self.session = URLSessionFactory.createSession(timeoutIntervalForRequest: timeout)
    }

    /// Creates a client with request timeout and optional SSL trusted domain.
    /// - Parameters:
    ///   - timeout: Timeout for each request in seconds.
    ///   - trustedSSLDomain: Domain whose server trust will be accepted by `URLSessionFactory`.
    public init(timeout: TimeInterval = 10, trustedSSLDomain: String?) {
        self.session = URLSessionFactory.createSession(
            timeoutIntervalForRequest: timeout,
            trustedSSLDomain: trustedSSLDomain
        )
    }

    /// Creates a client from an injected session (for custom config or testing).
    public init(session: URLSession) {
        self.session = session
    }

    /// Sends a raw request and returns unprocessed data + response.
    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await NetworkLogger.execute(request: request, session: session)
    }

    /// Sends a `GET` request and decodes JSON response.
    public func get<T: Decodable>(url: URL, headers: [String: String]? = nil) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await sendAndDecode(request)
    }

    /// Sends a `POST` request with `application/x-www-form-urlencoded` body and decodes JSON response.
    public func post<T: Decodable>(url: URL, parameters: [String: Any], headers: [String: String]? = nil) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.urlEncodedData
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await sendAndDecode(request)
    }

    /// Sends a `POST` request with JSON body and decodes JSON response.
    public func postJSON<T: Decodable, Body: Encodable>(url: URL, body: Body, headers: [String: String]? = nil) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await sendAndDecode(request)
    }

    /// Checks URL reachability by sending a `GET` and validating `2xx` status code.
    public func check(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue

        do {
            let (_, response) = try await send(request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200 ... 299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    /// Shared decode path for high-level helpers.
    private func sendAndDecode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await send(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw HTTPClientError.httpStatus(code: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HTTPClientError.decodingFailed(message: error.localizedDescription)
        }
    }
}
