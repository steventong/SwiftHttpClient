import Foundation

/// Builds configured `URLSession` instances for `HTTPClient`.
public enum URLSessionFactory {
    struct ManagedSession {
        let session: URLSession
        let trustDelegate: SSLTrustDelegate?
    }

    /// Creates a session with timeout configuration and a server trust policy.
    /// - Parameters:
    ///   - timeoutIntervalForRequest: Timeout applied to each request.
    ///   - timeoutIntervalForResource: Timeout applied to resource loading.
    ///   - serverTrustPolicy: Request-scoped certificate trust behavior.
    public static func createSession(timeoutIntervalForRequest: TimeInterval,
                                     timeoutIntervalForResource: TimeInterval = 10,
                                     serverTrustPolicy: ServerTrustPolicy = .system) -> URLSession {
        createManagedSession(
            timeoutIntervalForRequest: timeoutIntervalForRequest,
            timeoutIntervalForResource: timeoutIntervalForResource,
            serverTrustPolicy: serverTrustPolicy
        ).session
    }

    static func createManagedSession(
        timeoutIntervalForRequest: TimeInterval,
        timeoutIntervalForResource: TimeInterval = 10,
        serverTrustPolicy: ServerTrustPolicy = .system
    ) -> ManagedSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        configuration.timeoutIntervalForResource = timeoutIntervalForResource

        switch serverTrustPolicy {
        case .system:
            return ManagedSession(
                session: URLSession(configuration: configuration),
                trustDelegate: nil
            )
        case .userApprovedCertificate:
            let delegate = SSLTrustDelegate(policy: serverTrustPolicy)
            return ManagedSession(
                session: URLSession(
                    configuration: configuration,
                    delegate: delegate,
                    delegateQueue: nil
                ),
                trustDelegate: delegate
            )
        }
    }
}

/// Delegate that captures untrusted certificates and accepts only an approved fingerprint.
final class SSLTrustDelegate: NSObject, URLSessionDelegate {
    private let policy: ServerTrustPolicy
    private let lock = NSLock()
    private var certificateFailure: ServerCertificateInfo?

    init(policy: ServerTrustPolicy) {
        self.policy = policy
    }

    func consumeCertificateFailure() -> ServerCertificateInfo? {
        lock.lock()
        defer { lock.unlock() }
        let failure = certificateFailure
        certificateFailure = nil
        return failure
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let decision = ServerTrustEvaluator.evaluate(challenge.protectionSpace, policy: policy)
        if let failure = decision.failure {
            lock.lock()
            certificateFailure = failure
            lock.unlock()
        }
        completionHandler(decision.disposition, decision.credential)
    }
}
