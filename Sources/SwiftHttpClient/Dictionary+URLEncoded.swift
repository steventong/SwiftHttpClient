import Foundation

/// Utilities for URL form encoding.
public enum URLCoding {
    /// Percent-encodes query component text.
    public static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

public extension Dictionary where Key == String, Value == Any {
    /// Converts key-value pairs to `application/x-www-form-urlencoded` string.
    var urlEncodedString: String {
        map { key, value in
            let escapedKey = URLCoding.encode(key)
            let escapedValue = URLCoding.encode("\(value)")
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }

    /// UTF-8 encoded data of `urlEncodedString`.
    var urlEncodedData: Data? {
        urlEncodedString.data(using: .utf8)
    }
}
