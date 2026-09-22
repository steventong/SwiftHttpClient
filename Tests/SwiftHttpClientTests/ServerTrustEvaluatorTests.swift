import Foundation
import Security
import XCTest
@testable import SwiftHttpClient

final class ServerTrustEvaluatorTests: XCTestCase {
    func testUnapprovedSelfSignedCertificateIsRejectedWithItsFingerprint() throws {
        let space = try makeSpace()
        let result = ServerTrustEvaluator.evaluate(space, policy: .userApprovedCertificate(host: "nas.invalid", sha256Fingerprint: nil))
        XCTAssertEqual(result.disposition, .cancelAuthenticationChallenge)
        XCTAssertNil(result.credential)
        XCTAssertEqual(result.failure?.host, "nas.invalid")
        XCTAssertEqual(result.failure?.sha256Fingerprint.split(separator: ":").count, 32)
    }
    func testOnlyMatchingHostAndFingerprintCanApproveSelfSignedCertificate() throws {
        let space = try makeSpace()
        let fingerprint = try XCTUnwrap(ServerTrustEvaluator.evaluate(space, policy: .userApprovedCertificate(host: "nas.invalid", sha256Fingerprint: nil)).failure?.sha256Fingerprint)
        let approved = ServerTrustEvaluator.evaluate(space, policy: .userApprovedCertificate(host: "NAS.INVALID", sha256Fingerprint: fingerprint.lowercased()))
        XCTAssertEqual(approved.disposition, .useCredential)
        XCTAssertNotNil(approved.credential)
        XCTAssertNil(approved.failure)
        let changed = ServerTrustEvaluator.evaluate(space, policy: .userApprovedCertificate(host: "nas.invalid", sha256Fingerprint: "different"))
        XCTAssertEqual(changed.disposition, .cancelAuthenticationChallenge)
        let otherHost = ServerTrustEvaluator.evaluate(space, policy: .userApprovedCertificate(host: "other.invalid", sha256Fingerprint: fingerprint))
        XCTAssertEqual(otherHost.disposition, .performDefaultHandling)
        XCTAssertNil(otherHost.credential)
    }
    func testTrustedSystemChainDoesNotRequireAnExceptionFingerprint() throws {
        let space = try makeSpace(trusted: true)
        let result = ServerTrustEvaluator.evaluate(space, policy: .userApprovedCertificate(host: "nas.invalid", sha256Fingerprint: nil))
        XCTAssertEqual(result.disposition, .useCredential)
        XCTAssertNil(result.failure)
    }
    func testSystemPolicyAndNonTLSChallengesUseFoundationHandling() throws {
        XCTAssertEqual(ServerTrustEvaluator.evaluate(try makeSpace(), policy: .system).disposition, .performDefaultHandling)
        let password = URLProtectionSpace(host: "nas.invalid", port: 443, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        XCTAssertEqual(ServerTrustEvaluator.evaluate(password, policy: .userApprovedCertificate(host: "nas.invalid", sha256Fingerprint: "unused")).disposition, .performDefaultHandling)
    }
    private func makeSpace(trusted: Bool = false) throws -> TrustSpace {
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, try XCTUnwrap(Data(base64Encoded: certificateDER)) as CFData))
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "nas.invalid" as CFString), &trust), errSecSuccess)
        let value = try XCTUnwrap(trust)
        SecTrustSetNetworkFetchAllowed(value, false)
        SecTrustSetVerifyDate(value, Date(timeIntervalSince1970: 1790128190) as CFDate)
        if trusted {
            SecTrustSetAnchorCertificates(value, [certificate] as CFArray)
            SecTrustSetAnchorCertificatesOnly(value, true)
        }
        let space = TrustSpace(host: "nas.invalid", port: 443, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
        space.trust = value
        return space
    }
}
private final class TrustSpace: URLProtectionSpace, @unchecked Sendable {
    var trust: SecTrust?
    override var serverTrust: SecTrust? { trust }
}
private let certificateDER = "MIIDJjCCAg6gAwIBAgIUQ4wM/9dJ2VVevOQnY8b2lLbHV/8wDQYJKoZIhvcNAQELBQAwFjEUMBIGA1UEAwwLbmFzLmludmFsaWQwHhcNMjYwOTIyMDE0OTUwWhcNMjcwOTIyMDE0OTUwWjAWMRQwEgYDVQQDDAtuYXMuaW52YWxpZDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMLokew0yP7K19RztBFeKnpaGMtlX8tvbISIWl7ltzjCF4nZAhlt+lDcApjT/oMjfcyey25MLxLQpTeFpiPRUU8FGqqhJeSuhqxIubDph5rx17j6tayYqyy1K1E4ywUX7JYd97L4BtGBLVAVZHubopycDEr+ZPr9gqRH+KwZ53rcMtM23P8s5kbvr3CKBslTvGL/9ZJh03aLMvEj5pvOdSyK1fdHPAQjk4b1I4zWTbVLQEEBTcOQhyzaUswRTkV+8ssyo3qXpfR0xESarXDIh5stTmDOX2q4PgLbzF5wWEUw6VlSJSu6WWjwqPQzPf1Cs6cLo4VDiwQsysKb6PftrkkCAwEAAaNsMGowFgYDVR0RBA8wDYILbmFzLmludmFsaWQwDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCBaAwEwYDVR0lBAwwCgYIKwYBBQUHAwEwHQYDVR0OBBYEFMekPIQPA6Xi3aq1AG8Nea603KwxMA0GCSqGSIb3DQEBCwUAA4IBAQBon8ddGBBsLx7rH3fpAODsfvMJaCepZp9eANqugnvr3CMsYqASMfsI/spWsWp3wX+kuW2VDXl24LYeMVUQ9nw1gbTqDSa+cdsGfXqKVKZGXpMi9WoCTYo1CgACi5doMbcaZ08kQANKJnS2SZx9s0UMHBqCWWTdVk5CPZogshjDhCwDjeJ4UUdzZotB3Cb+oyUEeejMY6xtJREMLSQe4eJB6NY6l3RwIxWmc5qKNm2iANnF6GDtdWF6Ddu6/b+BZkcf3bUQA/q+n43z8PcFGASQY2/ImsQ33fXACM8J2dUDV7LEmj35+x01PdHYSLmbGHHeZPkhSFy7trR4iEB+Rmw6"
