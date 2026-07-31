import CryptoKit
import Foundation
import Security

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
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard case let .userApprovedCertificate(expectedHost, approvedFingerprint) = policy,
              challenge.protectionSpace.host.caseInsensitiveCompare(expectedHost) == .orderedSame
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if SecTrustEvaluateWithError(serverTrust, nil) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        guard let certificate = certificateInfo(
            trust: serverTrust,
            host: challenge.protectionSpace.host
        ) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if let approvedFingerprint,
           approvedFingerprint.caseInsensitiveCompare(certificate.sha256Fingerprint) == .orderedSame {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        lock.lock()
        certificateFailure = certificate
        lock.unlock()
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    private func certificateInfo(trust: SecTrust, host: String) -> ServerCertificateInfo? {
        guard let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
            return nil
        }

        let data = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: data)
        let fingerprint = digest
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")

        return ServerCertificateInfo(
            host: host,
            subject: SecCertificateCopySubjectSummary(certificate) as String? ?? host,
            sha256Fingerprint: fingerprint
        )
    }
}
