import Foundation

/// Information about the leaf certificate presented by a server.
public struct ServerCertificateInfo: Codable, Equatable, Sendable {
    public let host: String
    public let subject: String
    public let sha256Fingerprint: String

    public init(host: String, subject: String, sha256Fingerprint: String) {
        self.host = host
        self.subject = subject
        self.sha256Fingerprint = sha256Fingerprint
    }
}

/// Request-scoped server trust behavior.
public enum ServerTrustPolicy: Equatable, Sendable {
    /// Use the operating system trust store and hostname validation.
    case system

    /// Use system validation when possible. If it fails, accept only the
    /// explicitly approved SHA-256 leaf-certificate fingerprint.
    case userApprovedCertificate(host: String, sha256Fingerprint: String?)
}
