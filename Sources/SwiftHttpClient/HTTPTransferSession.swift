import Foundation

public enum HTTPTransferState: Sendable { case suspended, running, cancelling, completed }

/// A stable task handle. Foundation tasks never escape the transport implementation.
public final class HTTPTransferTask: @unchecked Sendable {
    fileprivate let native: URLSessionTask
    fileprivate init(_ task: URLSessionTask) { native = task }
    public var identifier: Int { native.taskIdentifier }
    public var context: String? {
        get { native.taskDescription }
        set { native.taskDescription = newValue }
    }
    public var response: URLResponse? { native.response }
    public var receivedBytes: Int64 { native.countOfBytesReceived }
    public var expectedBytes: Int64 { native.countOfBytesExpectedToReceive }
    public var priority: Float {
        get { native.priority }
        set { native.priority = newValue }
    }
    public var state: HTTPTransferState {
        switch native.state {
        case .running: .running
        case .suspended: .suspended
        case .canceling: .cancelling
        case .completed: .completed
        @unknown default: .completed
        }
    }
    public func resume() { native.resume() }
    public func cancel() { native.cancel() }
    public func cancelProducingResumeData(_ completion: @escaping @Sendable (Data?) -> Void) {
        guard let download = native as? URLSessionDownloadTask else { preconditionFailure("Only file downloads have resume data") }
        download.cancel(byProducingResumeData: completion)
    }
}

/// All callbacks run on the supplied serial queue. Download files must be moved before their callback returns.
public protocol HTTPTransferSessionDelegate: AnyObject {
    func transfer(_ task: HTTPTransferTask, accept response: URLResponse) -> Bool
    func transfer(_ task: HTTPTransferTask, received data: Data)
    func transfer(_ task: HTTPTransferTask, downloadedFileAt location: URL)
    func transfer(_ task: HTTPTransferTask, wrote bytes: Int64, total: Int64, expected: Int64)
    func transfer(_ task: HTTPTransferTask, completedWith error: Error?)
    func transferSessionFinishedBackgroundEvents()
}

public extension HTTPTransferSessionDelegate {
    func transfer(_ task: HTTPTransferTask, accept response: URLResponse) -> Bool { true }
    func transfer(_ task: HTTPTransferTask, received data: Data) {}
    func transfer(_ task: HTTPTransferTask, downloadedFileAt location: URL) {}
    func transfer(_ task: HTTPTransferTask, wrote bytes: Int64, total: Int64, expected: Int64) {}
    func transfer(_ task: HTTPTransferTask, completedWith error: Error?) {}
    func transferSessionFinishedBackgroundEvents() {}
}

/// Streaming, ranged and resumable background requests share the same trust evaluator as HTTPClient.
public final class HTTPTransferSession: @unchecked Sendable {
    private let session: URLSession
    private let bridge: TransferDelegate

    public init(configuration: URLSessionConfiguration, delegateQueue: OperationQueue,
                serverTrustPolicy: @escaping @Sendable (String) -> ServerTrustPolicy,
                delegate: any HTTPTransferSessionDelegate) {
        precondition(delegateQueue.maxConcurrentOperationCount == 1, "Transfer callbacks require an ordered delegate queue")
        bridge = TransferDelegate(policy: serverTrustPolicy, delegate: delegate)
        session = URLSession(configuration: configuration, delegate: bridge, delegateQueue: delegateQueue)
    }
    deinit { session.invalidateAndCancel() }

    public func dataTask(for request: URLRequest) -> HTTPTransferTask {
        bridge.task(session.dataTask(with: request))
    }
    public func downloadTask(for request: URLRequest) -> HTTPTransferTask {
        bridge.task(session.downloadTask(with: request))
    }
    public func downloadTask(resumeData: Data) -> HTTPTransferTask {
        bridge.task(session.downloadTask(withResumeData: resumeData))
    }
    public func tasks(_ completion: @escaping @Sendable ([HTTPTransferTask]) -> Void) {
        session.getAllTasks { [bridge] tasks in completion(tasks.map { bridge.task($0) }) }
    }
    public func invalidateAndCancel() { session.invalidateAndCancel() }
}

private final class TransferDelegate: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    private weak var delegate: (any HTTPTransferSessionDelegate)?
    private let policy: @Sendable (String) -> ServerTrustPolicy
    private let lock = NSLock()
    private var tasks: [Int: HTTPTransferTask] = [:]
    private var taskFailures: [Int: Error] = [:]

    init(policy: @escaping @Sendable (String) -> ServerTrustPolicy, delegate: any HTTPTransferSessionDelegate) {
        self.policy = policy
        self.delegate = delegate
    }
    func task(_ native: URLSessionTask) -> HTTPTransferTask {
        lock.lock()
        defer { lock.unlock() }
        if let existing = tasks[native.taskIdentifier] { return existing }
        let task = HTTPTransferTask(native)
        if native.state != .completed { tasks[native.taskIdentifier] = task }
        return task
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let decision = ServerTrustEvaluator.evaluate(challenge.protectionSpace, policy: policy(challenge.protectionSpace.host))
        // Connection-level rejections remain Foundation TLS errors; do not assign one connection's certificate to other tasks.
        completionHandler(decision.disposition, decision.credential)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let decision = ServerTrustEvaluator.evaluate(challenge.protectionSpace, policy: policy(challenge.protectionSpace.host))
        if let certificate = decision.failure {
            lock.lock()
            taskFailures[task.taskIdentifier] = HTTPClientError.serverCertificateUntrusted(certificate)
            lock.unlock()
        }
        completionHandler(decision.disposition, decision.credential)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let accepted = delegate?.transfer(task(dataTask), accept: response) ?? false
        completionHandler(accepted ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        delegate?.transfer(task(dataTask), received: data)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        delegate?.transfer(task(downloadTask), downloadedFileAt: location)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        delegate?.transfer(task(downloadTask), wrote: bytesWritten, total: totalBytesWritten, expected: totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, task native: URLSessionTask, didCompleteWithError error: Error?) {
        let handle = task(native)
        lock.lock()
        let failure = taskFailures.removeValue(forKey: native.taskIdentifier) ?? error
        tasks[native.taskIdentifier] = nil
        lock.unlock()
        delegate?.transfer(handle, completedWith: failure)
    }
    @available(macOS 11.0, *)
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        delegate?.transferSessionFinishedBackgroundEvents()
    }
}
