import Foundation

/// A lightweight async HTTP client with typed decoding helpers.
public final class HTTPClient {
    private struct ManagedSessionConfig {
        var timeoutIntervalForRequest: TimeInterval
        var timeoutIntervalForResource: TimeInterval
        var serverTrustPolicy: ServerTrustPolicy
    }

    private let lock = NSLock()
    private var session: URLSession
    private var trustDelegate: SSLTrustDelegate?
    private var managedSessionConfig: ManagedSessionConfig?

    /// Creates a client with request timeout.
    /// - Parameter timeout: Timeout for each request in seconds.
    public init(timeout: TimeInterval = 10) {
        let managedSession = URLSessionFactory.createManagedSession(
            timeoutIntervalForRequest: timeout
        )
        managedSessionConfig = ManagedSessionConfig(
            timeoutIntervalForRequest: timeout,
            timeoutIntervalForResource: 10,
            serverTrustPolicy: .system
        )
        session = managedSession.session
        trustDelegate = managedSession.trustDelegate
    }

    /// Creates a client with request timeout and request-scoped server trust policy.
    /// - Parameters:
    ///   - timeout: Timeout for each request in seconds.
    ///   - serverTrustPolicy: Certificate validation and user-approved fingerprint policy.
    public init(timeout: TimeInterval = 10, serverTrustPolicy: ServerTrustPolicy) {
        let managedSession = URLSessionFactory.createManagedSession(
            timeoutIntervalForRequest: timeout,
            serverTrustPolicy: serverTrustPolicy
        )
        managedSessionConfig = ManagedSessionConfig(
            timeoutIntervalForRequest: timeout,
            timeoutIntervalForResource: 10,
            serverTrustPolicy: serverTrustPolicy
        )
        session = managedSession.session
        trustDelegate = managedSession.trustDelegate
    }

    /// Creates a client from an injected session (for custom config or testing).
    public init(session: URLSession) {
        managedSessionConfig = nil
        self.session = session
        trustDelegate = nil
    }

    /// Sends a raw request and returns unprocessed data + response.
    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await NetworkLogger.execute(request: request, session: currentSession)
        } catch {
            if let certificate = currentTrustDelegate?.consumeCertificateFailure() {
                throw HTTPClientError.serverCertificateUntrusted(certificate)
            }
            throw error
        }
    }

    /// Downloads a response body to a caller-owned temporary file.
    ///
    /// The file is moved out of URLSession's transient download location before
    /// this method returns. The caller is responsible for removing it.
    public func download(_ request: URLRequest) async throws -> (URL, URLResponse) {
        do {
            return try await NetworkLogger.download(
                request: request,
                session: currentSession
            )
        } catch {
            if let certificate = currentTrustDelegate?.consumeCertificateFailure() {
                throw HTTPClientError.serverCertificateUntrusted(certificate)
            }
            throw error
        }
    }

    /// Updates server trust policy at runtime by rebuilding the managed `URLSession`.
    public func updateServerTrustPolicy(_ policy: ServerTrustPolicy) {
        lock.lock()
        defer { lock.unlock() }

        guard var config = managedSessionConfig else {
            Logger.warn("HTTPClient#updateServerTrustPolicy ignored: client was initialized with custom session")
            return
        }

        config.serverTrustPolicy = policy
        managedSessionConfig = config
        let managedSession = URLSessionFactory.createManagedSession(
            timeoutIntervalForRequest: config.timeoutIntervalForRequest,
            timeoutIntervalForResource: config.timeoutIntervalForResource,
            serverTrustPolicy: config.serverTrustPolicy
        )
        session = managedSession.session
        trustDelegate = managedSession.trustDelegate
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

    private var currentSession: URLSession {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    private var currentTrustDelegate: SSLTrustDelegate? {
        lock.lock()
        defer { lock.unlock() }
        return trustDelegate
    }
}
