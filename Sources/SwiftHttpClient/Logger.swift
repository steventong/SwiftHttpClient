import Foundation
import OSLog

public final class Logger {
    private static let osLog = OSLog(subsystem: "me.itwl.SwiftHttpClient", category: "SwiftHttpClient")

    private init() {}

    public static func info(_ message: String, filePath: String = #fileID, fileNumber: Int = #line) {
        log(message, type: .info, filePath: filePath, fileNumber: fileNumber)
    }

    public static func debug(_ message: String, filePath: String = #fileID, fileNumber: Int = #line) {
        log(message, type: .debug, filePath: filePath, fileNumber: fileNumber)
    }

    public static func warn(_ message: String, filePath: String = #fileID, fileNumber: Int = #line) {
        log(message, type: .error, filePath: filePath, fileNumber: fileNumber)
    }

    public static func error(_ message: String, filePath: String = #fileID, fileNumber: Int = #line) {
        log(message, type: .fault, filePath: filePath, fileNumber: fileNumber)
    }

    private static func log(_ message: String, type: OSLogType, filePath: String, fileNumber: Int) {
        let swiftFileName = (filePath as NSString).lastPathComponent
        os_log("[%{public}@:%{public}d] %{public}@", log: osLog, type: type, swiftFileName, fileNumber, message)
    }
}
