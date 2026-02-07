import Foundation

/// Builds configured `URLSession` instances for `HTTPClient`.
public enum URLSessionFactory {

    /// Creates a session with timeout configuration and optional trusted SSL domain.
    /// - Parameters:
    ///   - timeoutIntervalForRequest: Timeout applied to each request.
    ///   - timeoutIntervalForResource: Timeout applied to resource loading.
    ///   - trustedSSLDomain: When provided, trusts server certificates for this host.
    public static func createSession(timeoutIntervalForRequest: TimeInterval,
                                     timeoutIntervalForResource: TimeInterval = 10,
                                     trustedSSLDomain: String? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        configuration.timeoutIntervalForResource = timeoutIntervalForResource

        if let domain = trustedSSLDomain {
            Logger.info("URLSessionFactory#createSession, trust ssl cert: \(domain)")
            let delegate = SSLTrustDelegate(trustedDomain: domain)
            return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        }

        return URLSession(configuration: configuration)
    }
}

/// Delegate that accepts server trust for one configured domain.
final class SSLTrustDelegate: NSObject, URLSessionDelegate {
    private let trustedDomain: String

    init(trustedDomain: String) {
        self.trustedDomain = trustedDomain
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == trustedDomain,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }
}
