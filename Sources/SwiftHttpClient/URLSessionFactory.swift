import Foundation

public enum URLSessionFactory {
    public static func createSession(
        timeoutIntervalForRequest: TimeInterval,
        timeoutIntervalForResource: TimeInterval = 10,
        trustedSSLDomain: String? = nil
    ) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        configuration.timeoutIntervalForResource = timeoutIntervalForResource

        if let domain = trustedSSLDomain {
            let delegate = SSLTrustDelegate(trustedDomain: domain)
            #if DEBUG
                Logger.info("URLSessionFactory#createSession, trust ssl cert: \(domain)")
            #endif
            return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        }

        return URLSession(configuration: configuration)
    }
}

final class SSLTrustDelegate: NSObject, URLSessionDelegate {
    private let trustedDomain: String

    init(trustedDomain: String) {
        self.trustedDomain = trustedDomain
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
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
