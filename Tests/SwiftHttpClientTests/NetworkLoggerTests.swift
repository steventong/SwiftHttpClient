import Foundation
import XCTest
@testable import SwiftHttpClient

final class NetworkLoggerTests: XCTestCase {
    func testDiagnosticURLRemovesCredentialsQueryAndFragment() {
        let url = URL(string: "https://user:secret@example.com:5001/webapi/entry.cgi?passwd=secret&sid=token#secret")!
        XCTAssertEqual(NetworkLogger.diagnosticURL(url), "https://example.com:5001/webapi/entry.cgi")
    }
}
