import Foundation

public enum URLCoding {
    public static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

public extension Dictionary where Key == String, Value == Any {
    var urlEncodedString: String {
        map { key, value in
            let escapedKey = URLCoding.encode(key)
            let escapedValue = URLCoding.encode("\(value)")
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }

    var urlEncodedData: Data? {
        urlEncodedString.data(using: .utf8)
    }
}
