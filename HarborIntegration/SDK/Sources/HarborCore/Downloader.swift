import Foundation

/// One bounded HTTPS request per object. Delegate serialization owns bytes, completion and file lifetime.
public final class Download: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var handle: FileHandle?
    private var continuation: CheckedContinuation<URL, Error>?
    private var count: Int64 = 0
    private var limit: Int64 = 0
    private var exact: Int64?
    private var destination: URL!
    private var progress: @Sendable (Double) -> Void = { _ in }
    private let state = NSLock()
    private var activeTask: URLSessionDataTask?
    private var cancellationRequested = false
    private var fixtureConfiguration: URLSessionConfiguration?
    public override init() { super.init() }
    init(configuration: URLSessionConfiguration) { fixtureConfiguration = configuration; super.init() }
    public func cancel() {
        state.lock(); cancellationRequested = true; let task = activeTask; state.unlock(); task?.cancel()
    }
    public func fetch(_ url: URL, to destination: URL, limit: Int64, exact: Int64? = nil, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try CatalogVerifier.secureURL(url)
        guard !SafeFiles.exists(destination) else { throw HarborError("Download staging file already exists.") }
        self.destination = destination; self.limit = limit; self.exact = exact; self.progress = progress
        guard SafeFiles.fm.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw HarborError("Cannot create a download file.") }
        handle = try FileHandle(forWritingTo: destination)
        let config = fixtureConfiguration ?? URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 600
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                var request = URLRequest(url: url); request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let task = session.dataTask(with: request)
                state.lock(); activeTask = task; let cancelled = cancellationRequested; state.unlock()
                task.resume(); if cancelled { task.cancel() }
            }
        }, onCancel: { self.cancel() })
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, (try? CatalogVerifier.secureURL(url)) != nil else { completionHandler(nil); return }
        completionHandler(request)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let url = response.url, (try? CatalogVerifier.secureURL(url)) != nil,
              response.expectedContentLength <= limit,
              exact == nil || response.expectedContentLength < 0 || response.expectedContentLength == exact else {
            completionHandler(.cancel); finish(.failure(HarborError("The download server returned an unexpected status or size."))); return
        }
        completionHandler(.allow)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard continuation != nil else { return }
        do {
            count += Int64(data.count)
            guard count <= limit else { throw HarborError("The download exceeds its authenticated size limit.") }
            try handle?.write(contentsOf: data)
            if let exact { progress(Double(count) / Double(exact)) }
        } catch { dataTask.cancel(); finish(.failure(error)) }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard continuation != nil else { return }
        if let error { finish(.failure(error)); return }
        do {
            guard exact == nil || exact == count else { throw HarborError("The download is incomplete. Try again.") }
            try handle?.synchronize()
            finish(.success(destination))
        } catch { finish(.failure(error)) }
    }
    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        try? handle?.close(); handle = nil
        if case .failure = result { try? SafeFiles.fm.removeItem(at: destination) }
        session.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
