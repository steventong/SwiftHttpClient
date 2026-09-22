import Foundation
import XCTest
@testable import SwiftHttpClient

final class HTTPTransferSessionTests: XCTestCase {
    override func tearDown() { TransferProtocol.handler = nil; super.tearDown() }

    func testStreamsFirstChunkBeforeTheResponseFinishesAndKeepsHandleIdentity() async throws {
        let firstChunk = expectation(description: "First chunk delivered")
        let firstBytes = Data(repeating: 1, count: 64 * 1024)
        let lastBytes = Data(repeating: 2, count: 64 * 1024)
        let finished = expectation(description: "Completed")
        let delegate = TransferProbe()
        let stream = ProtocolGate()
        let session = makeSession(delegate: delegate)
        var request = URLRequest(url: URL(string: "https://nas.invalid/media?sid=private")!)
        request.setValue("bytes=10-131081", forHTTPHeaderField: "Range")
        let handle = session.dataTask(for: request)
        handle.context = "original-owner"
        delegate.response = { task, response in
            XCTAssertTrue(task === handle)
            XCTAssertEqual(task.context, "original-owner")
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 206)
            return true
        }
        delegate.received = { task, data in
            XCTAssertTrue(task === handle)
            delegate.append(data)
            if delegate.data.count == firstBytes.count { firstChunk.fulfill() }
        }
        delegate.completed = { task, error in
            XCTAssertTrue(task === handle)
            XCTAssertNil(error)
            finished.fulfill()
        }
        TransferProtocol.handler = { proto in
            XCTAssertEqual(proto.request.value(forHTTPHeaderField: "Range"), "bytes=10-131081")
            proto.respond(status: 206, headers: ["Content-Length": "131072", "Content-Range": "bytes 10-131081/131082"])
            stream.set { proto.send(lastBytes); proto.finish() }
            proto.send(firstBytes)
        }
        handle.resume()
        await fulfillment(of: [firstChunk], timeout: 3)
        XCTAssertEqual(delegate.data, firstBytes)
        stream.release()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(delegate.data, firstBytes + lastBytes)
        withExtendedLifetime(session) {}
    }

    func testTaskEnumerationPreservesOpaqueContextAndTheSameHandle() async throws {
        let delegate = TransferProbe()
        let session = makeSession(delegate: delegate)
        let task = session.dataTask(for: URLRequest(url: URL(string: "https://nas.invalid/media")!))
        task.context = "persisted-context"
        let started = expectation(description: "Registered request")
        let gate = ProtocolGate()
        TransferProtocol.handler = { proto in
            proto.respond(status: 200, headers: [:])
            gate.set { proto.finish() }
            started.fulfill()
        }
        task.resume()
        await fulfillment(of: [started], timeout: 3)
        let tasks = await withCheckedContinuation { continuation in session.tasks { continuation.resume(returning: $0) } }
        let restored = try XCTUnwrap(tasks.first(where: { $0.identifier == task.identifier }))
        XCTAssertTrue(restored === task)
        XCTAssertEqual(restored.context, "persisted-context")
        XCTAssertEqual(restored.state, .running)
        task.cancel()
    }

    func testFileIsAvailableUntilSynchronousDelegateReturns() async throws {
        let completed = expectation(description: "File transfer completed")
        let delegate = TransferProbe()
        let session = makeSession(delegate: delegate)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        TransferProtocol.handler = { proto in
            proto.respond(status: 200, headers: ["Content-Length": "4"])
            proto.send(Data([1, 2, 3, 4])); proto.finish()
        }
        delegate.downloaded = { _, location in
            do { try FileManager.default.moveItem(at: location, to: destination) }
            catch { XCTFail("File callback must own a live temporary file: \(error)") }
        }
        delegate.completed = { _, error in XCTAssertNil(error); completed.fulfill() }
        session.downloadTask(for: URLRequest(url: URL(string: "https://nas.invalid/file")!)).resume()
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3, 4]))
        withExtendedLifetime(session) {}
    }

    func testRejectingResponseDoesNotDeliverBodyAndCompletesAsCancelled() async {
        let completed = expectation(description: "Rejected response")
        let delegate = TransferProbe()
        let session = makeSession(delegate: delegate)
        TransferProtocol.handler = { proto in
            proto.respond(status: 403, headers: ["Content-Length": "2"])
            proto.send(Data([1, 2])); proto.finish()
        }
        delegate.response = { _, _ in false }
        delegate.received = { _, _ in XCTFail("Rejected body") }
        delegate.completed = { _, error in
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
            completed.fulfill()
        }
        session.dataTask(for: URLRequest(url: URL(string: "https://nas.invalid/denied")!)).resume()
        await fulfillment(of: [completed], timeout: 3)
        withExtendedLifetime(session) {}
    }

    func testSuspendedFileDownloadCanCancelWithResumeDataCallback() async {
        let cancelled = expectation(description: "Resume data callback")
        let delegate = TransferProbe()
        let session = makeSession(delegate: delegate)
        let task = session.downloadTask(for: URLRequest(url: URL(string: "https://nas.invalid/file")!))
        task.cancelProducingResumeData { _ in cancelled.fulfill() }
        await fulfillment(of: [cancelled], timeout: 3)
        withExtendedLifetime(session) {}
    }

    private func makeSession(delegate: TransferProbe) -> HTTPTransferSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransferProtocol.self]
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return HTTPTransferSession(configuration: config, delegateQueue: queue, serverTrustPolicy: { _ in .system }, delegate: delegate)
    }
}

private final class TransferProbe: HTTPTransferSessionDelegate {
    var response: (HTTPTransferTask, URLResponse) -> Bool = { _, _ in true }
    var received: (HTTPTransferTask, Data) -> Void = { _, _ in }
    var downloaded: (HTTPTransferTask, URL) -> Void = { _, _ in }
    var completed: (HTTPTransferTask, Error?) -> Void = { _, _ in }
    private let lock = NSLock()
    private var bytes = Data()
    var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
    func append(_ data: Data) { lock.lock(); defer { lock.unlock() }; bytes.append(data) }
    func transfer(_ task: HTTPTransferTask, accept response: URLResponse) -> Bool { self.response(task, response) }
    func transfer(_ task: HTTPTransferTask, received data: Data) { received(task, data) }
    func transfer(_ task: HTTPTransferTask, downloadedFileAt location: URL) { downloaded(task, location) }
    func transfer(_ task: HTTPTransferTask, completedWith error: Error?) { completed(task, error) }
}

private final class ProtocolGate: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (() -> Void)?
    func set(_ action: @escaping () -> Void) { lock.lock(); self.action = action; lock.unlock() }
    func release() { lock.lock(); let action = action; self.action = nil; lock.unlock(); action?() }
}

private final class TransferProtocol: URLProtocol {
    static var handler: ((TransferProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() {}
    func respond(status: Int, headers: [String: String]) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
    }
    func send(_ data: Data) { client?.urlProtocol(self, didLoad: data) }
    func finish() { client?.urlProtocolDidFinishLoading(self) }
}
