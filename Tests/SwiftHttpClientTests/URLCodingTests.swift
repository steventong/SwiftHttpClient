import XCTest
@testable import SwiftHttpClient

final class URLCodingTests: XCTestCase {
    func testFormEncodingEscapesReservedSeparatorsAndUnicode() {
        XCTAssertEqual(
            URLCoding.encode("伍佰 &amp; China Blue=live+test?"),
            "%E4%BC%8D%E4%BD%B0%20%26amp%3B%20China%20Blue%3Dlive%2Btest%3F"
        )
    }

    func testDictionaryFormEncodingDoesNotSplitJSONAtAmpersand() {
        let parameters: [String: Any] = [
            "data": #"[{"lyrics":"伍佰 &amp; China Blue"}]"#
        ]

        let encoded = parameters.urlEncodedString

        XCTAssertEqual(
            encoded,
            "data=%5B%7B%22lyrics%22%3A%22%E4%BC%8D%E4%BD%B0%20%26amp%3B%20China%20Blue%22%7D%5D"
        )
        XCTAssertEqual(encoded.filter { $0 == "&" }.count, 0)
    }
}
