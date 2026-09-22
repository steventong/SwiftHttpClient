#if os(macOS)
import CryptoKit
import Foundation
import XCTest
@testable import SwiftHttpClient

final class HTTPTransferTLSTests: XCTestCase {
    func testRealSelfSignedTLSRequiresTheApprovedHostAndExactFingerprint() async throws {
        let server = try LocalTLSServer()
        for (host, fingerprint, shouldSucceed) in [
            ("127.0.0.1", Optional<String>.none, false),
            ("127.0.0.1", Optional(server.fingerprint), true),
            ("127.0.0.1", Optional("00"), false),
            ("other.invalid", Optional(server.fingerprint), false)
        ] {
            let completed = expectation(description: "TLS decision \(host) \(shouldSucceed)")
            let probe = TLSProbe(completed)
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.urlCredentialStorage = nil
            config.connectionProxyDictionary = [:]
            config.timeoutIntervalForRequest = 5
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = HTTPTransferSession(configuration: config, delegateQueue: queue,
                                              serverTrustPolicy: { _ in .userApprovedCertificate(host: host, sha256Fingerprint: fingerprint) },
                                              delegate: probe)
            session.dataTask(for: URLRequest(url: server.url)).resume()
            await fulfillment(of: [completed], timeout: 10)
            let (data, error) = probe.result
            if shouldSucceed {
                XCTAssertNil(error)
                XCTAssertEqual(data, Data("transfer-through-approved-tls".utf8))
            } else {
                XCTAssertNotNil(error)
                XCTAssertTrue(data.isEmpty)
            }
            session.invalidateAndCancel()
        }
        withExtendedLifetime(server) {}
    }
}

private final class TLSProbe: HTTPTransferSessionDelegate {
    private let lock = NSLock()
    private var data = Data()
    private var error: Error?
    private let completed: XCTestExpectation
    init(_ completed: XCTestExpectation) { self.completed = completed }
    var result: (Data, Error?) { lock.withLock { (data, error) } }
    func transfer(_ task: HTTPTransferTask, received data: Data) { lock.withLock { self.data.append(data) } }
    func transfer(_ task: HTTPTransferTask, completedWith error: Error?) {
        lock.withLock { self.error = error }
        completed.fulfill()
    }
}

/// Ephemeral TLS fixture: no certificates or keys are installed into a user keychain.
private final class LocalTLSServer {
    let url: URL
    let fingerprint: String
    private let directory: URL
    private let process: Process

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        process = Process()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let key = directory.appendingPathComponent("key.pem").path
            let cert = directory.appendingPathComponent("cert.pem").path
            let der = directory.appendingPathComponent("cert.der")
            try Self.runOpenSSL(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key,
                                 "-out", cert, "-days", "1", "-subj", "/CN=127.0.0.1"])
            try Self.runOpenSSL(["x509", "-in", cert, "-outform", "DER", "-out", der.path])
            fingerprint = SHA256.hash(data: try Data(contentsOf: der)).map { String(format: "%02X", $0) }.joined(separator: ":")
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-I", "-u", "-c", """
            import http.server, ssl, sys
            class Handler(http.server.BaseHTTPRequestHandler):
                protocol_version = 'HTTP/1.1'
                def log_message(self, *args): pass
                def do_GET(self):
                    body = b'transfer-through-approved-tls'
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(body)))
                    self.send_header('Cache-Control', 'no-store')
                    self.send_header('Connection', 'close')
                    self.end_headers()
                    self.wfile.write(body)
                    self.close_connection = True
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(sys.argv[1], sys.argv[2])
            server.socket = context.wrap_socket(server.socket, server_side=True)
            print(server.server_port, flush=True)
            server.serve_forever()
            """, cert, key]
            process.standardOutput = output
            process.standardError = Pipe()
            try process.run()
            var line = Data()
            while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
                if byte.first == 10 { break }
                line.append(byte)
            }
            guard let port = Int(String(decoding: line, as: UTF8.self)), (1...65535).contains(port),
                  let endpoint = URL(string: "https://127.0.0.1:\(port)/stream") else {
                throw NSError(domain: "TLSFixture", code: 1)
            }
            url = endpoint
        } catch {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func runOpenSSL(_ arguments: [String]) throws {
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        command.arguments = arguments
        command.standardOutput = Pipe()
        command.standardError = Pipe()
        try command.run()
        command.waitUntilExit()
        guard command.terminationStatus == 0 else { throw NSError(domain: "TLSFixture", code: Int(command.terminationStatus)) }
    }
}
#endif
