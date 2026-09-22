import CryptoKit
import Foundation
import Security

/// One certificate decision path for request, streaming and background transports.
enum ServerTrustEvaluator {
    struct Decision {
        let disposition: URLSession.AuthChallengeDisposition
        let credential: URLCredential?
        let failure: ServerCertificateInfo?
    }

    static func evaluate(_ protectionSpace: URLProtectionSpace, policy: ServerTrustPolicy) -> Decision {
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = protectionSpace.serverTrust,
              case let .userApprovedCertificate(expectedHost, fingerprint) = policy,
              protectionSpace.host.caseInsensitiveCompare(expectedHost) == .orderedSame else {
            return Decision(disposition: .performDefaultHandling, credential: nil, failure: nil)
        }
        if SecTrustEvaluateWithError(trust, nil) {
            return Decision(disposition: .useCredential, credential: URLCredential(trust: trust), failure: nil)
        }
        guard let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
            return Decision(disposition: .cancelAuthenticationChallenge, credential: nil, failure: nil)
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
        let info = ServerCertificateInfo(host: protectionSpace.host,
                                        subject: SecCertificateCopySubjectSummary(certificate) as String? ?? protectionSpace.host,
                                        sha256Fingerprint: digest.map { String(format: "%02X", $0) }.joined(separator: ":"))
        if fingerprint?.caseInsensitiveCompare(info.sha256Fingerprint) == .orderedSame {
            return Decision(disposition: .useCredential, credential: URLCredential(trust: trust), failure: nil)
        }
        return Decision(disposition: .cancelAuthenticationChallenge, credential: nil, failure: info)
    }
}
