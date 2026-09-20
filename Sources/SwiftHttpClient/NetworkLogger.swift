import Foundation

/// Logs transport summaries without request or response payloads.
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
                    statusCode: httpResponse.statusCode,
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
                statusCode: nil,
                duration: duration,
                error: error
            )
            throw error
        }
    }

    /// Executes a download request with timing/logging and preserves the file.
    public static func download(
        request: URLRequest,
        session: URLSession = .shared
    ) async throws -> (URL, URLResponse) {
        let startTime = Date()
        let url = request.url ?? URL(string: "unknown://url")!
        let method = request.httpMethod ?? "GET"

        do {
            let result = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
                session.downloadTask(with: request) { temporaryURL, response, error in
                    do {
                        if let error {
                            throw error
                        }
                        guard let temporaryURL, let response else {
                            throw URLError(.badServerResponse)
                        }

                        let destination = FileManager.default.temporaryDirectory
                            .appendingPathComponent("swift-http-download-\(UUID().uuidString)")
                        try FileManager.default.moveItem(
                            at: temporaryURL,
                            to: destination
                        )
                        continuation.resume(returning: (destination, response))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }.resume()
            }
            let duration = Date().timeIntervalSince(startTime)
            let httpResponse = result.1 as? HTTPURLResponse
            logCombined(
                url: url,
                method: method,
                statusCode: httpResponse?.statusCode,
                duration: duration,
                error: nil
            )
            return result
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logCombined(
                url: url,
                method: method,
                statusCode: nil,
                duration: duration,
                error: error
            )
            throw error
        }
    }

    private static func logCombined(
        url: URL,
        method: String,
        statusCode: Int?,
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
        lines.append("[HTTP] \(method) \(diagnosticURL(url))")
        lines.append("Summary: status=\(statusText) result=\(statusMark) duration=\(durationStr)s")

        if let error {
            let nsError = error as NSError
            lines.append("Error: domain=\(nsError.domain) code=\(nsError.code)")
            Logger.error(lines.joined(separator: "\n"))
        } else {
            Logger.debug(lines.joined(separator: "\n"))
        }
    }

    /// Keep credentials and arbitrary payloads out of transport diagnostics.
    static func diagnosticURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid URL>"
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "<invalid URL>"
    }
}
