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
        let statusEmoji: String
        let statusText: String

        if error != nil {
            statusEmoji = "FAIL"
            statusText = "ERROR"
        } else if let code = statusCode {
            statusEmoji = (200 ... 299).contains(code) ? "OK" : "FAIL"
            statusText = "\(code)"
        } else {
            statusEmoji = "UNKNOWN"
            statusText = "?"
        }

        var log = "\n[HTTP] [\(method)] [\(statusEmoji)] [\(statusText)] [\(durationStr)s]"
        log += "\nURL: \(url.absoluteString)"

        if let reqHeaders = requestHeaders, !reqHeaders.isEmpty {
            log += "\nRequest Headers:"
            for (key, value) in reqHeaders {
                log += "\n  \(key): \(value)"
            }
        }

        if let body = requestBody, let bodyString = String(data: body, encoding: .utf8) {
            log += "\nRequest Body: \(bodyString)"
        }

        if let error = error {
            log += "\nError: \(error.localizedDescription)"
            log += "\nDetails: \(error)"
            Logger.error(log)
            return
        }

        if let respHeaders = responseHeaders, !respHeaders.isEmpty {
            log += "\nResponse Headers:"
            for (key, value) in respHeaders {
                log += "\n  \(key): \(value)"
            }
        }

        if let data = responseData {
            if let prettyJSON = prettyPrintJSON(data) {
                log += "\nResponse Body:\n\(prettyJSON)"
            } else if let bodyString = String(data: data, encoding: .utf8) {
                log += "\nResponse Body: \(bodyString)"
            }
        }

        Logger.debug(log)
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
