import Foundation
import XCTest
@testable import SwiftHttpClient

final class HTTPClientDownloadTests: XCTestCase {
    override func tearDown() {
        DownloadURLProtocol.handler = nil
        super.tearDown()
    }

    func testDownloadPreservesResponseInCallerOwnedTemporaryFile() async throws {
        let expected = Data([0x49, 0x44, 0x33, 0x04])
        DownloadURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "audio/mpeg"]
            )!
            return (response, expected)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadURLProtocol.self]
        let client = HTTPClient(session: URLSession(configuration: configuration))
        let request = URLRequest(url: URL(string: "https://nas.local/audio.mp3")!)

        let (fileURL, response) = try await client.download(request)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: fileURL), expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }
}

private final class DownloadURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.unknown)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
