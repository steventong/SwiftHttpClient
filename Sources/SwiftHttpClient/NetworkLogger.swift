import Foundation

/// Logs request and response details for network execution.
public enum NetworkLogger {
    /// Executes request with timing/logging and rethrows any network error.
    public static func execute(request: URLRequest, session: URLSession = .shared) async throws -> (Data, URLResponse) {
        let startTime = Date()
        let url = request.url ?? URL(string: "unknown://url")!
        let method = request.httpMethod ?? "GET"

        do {
            let (data, response) = try await session.data(for: request)
            let duration = Date().timeIntervalSince(startTime)

            if let httpResponse = response as? HTTPURLResponse {
                logCombined(
                    url: url,
                    method: method,
                    requestHeaders: request.allHTTPHeaderFields,
                    requestBody: request.httpBody,
                    statusCode: httpResponse.statusCode,
                    responseHeaders: httpResponse.allHeaderFields,
                    responseData: data,
                    duration: duration,
                    error: nil
                )
            }

            return (data, response)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logCombined(
                url: url,
                method: method,
                requestHeaders: request.allHTTPHeaderFields,
                requestBody: request.httpBody,
                statusCode: nil,
                responseHeaders: nil,
                responseData: nil,
                duration: duration,
                error: error
            )
            throw error
        }
    }

    private static func logCombined(
        url: URL,
        method: String,
        requestHeaders: [String: String]?,
        requestBody: Data?,
        statusCode: Int?,
        responseHeaders: [AnyHashable: Any]?,
        responseData: Data?,
        duration: TimeInterval,
        error: Error?
    ) {
        let durationStr = String(format: "%.3f", duration)
        let statusMark: String
        let statusText: String

        if error != nil {
            statusMark = "FAIL"
            statusText = "ERROR"
        } else if let code = statusCode {
            statusMark = (200 ... 299).contains(code) ? "OK" : "FAIL"
            statusText = "\(code)"
        } else {
            statusMark = "UNKNOWN"
            statusText = "?"
        }

        var lines: [String] = []
        lines.append("")
        lines.append("[HTTP] \(method) \(url.absoluteString)")
        lines.append("Summary: status=\(statusText) result=\(statusMark) duration=\(durationStr)s")

        if let reqHeaders = requestHeaders, !reqHeaders.isEmpty {
            lines.append("Request Headers:")
            for (key, value) in reqHeaders.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
                lines.append("  - \(key): \(value)")
            }
        }

        if let body = requestBody, let bodyString = String(data: body, encoding: .utf8) {
            lines.append("Request Body:")
            lines.append(bodyString)
        }

        if let error = error {
            lines.append("Error: \(error.localizedDescription)")
            lines.append("Details: \(error)")
            Logger.error(lines.joined(separator: "\n"))
            return
        }

        if let respHeaders = responseHeaders, !respHeaders.isEmpty {
            lines.append("Response Headers:")
            for (key, value) in respHeaders.sorted(by: { "\($0.key)".localizedCaseInsensitiveCompare("\($1.key)") == .orderedAscending }) {
                lines.append("  - \(key): \(value)")
            }
        }

        if let data = responseData {
            if let prettyJSON = prettyPrintJSON(data) {
                lines.append("Response Body:")
                lines.append(prettyJSON)
            } else if let bodyString = String(data: data, encoding: .utf8) {
                lines.append("Response Body:")
                lines.append(bodyString)
            }
        }

        Logger.debug(lines.joined(separator: "\n"))
    }

    /// Pretty-prints JSON payloads when possible for readable output.
    private static func prettyPrintJSON(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }
}
