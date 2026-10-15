import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ArtworkHTTPClient: Sendable {
    func image(at url: URL, maximumBytes: Int64) async throws -> Data?
}

public enum ArtworkDownloadError: Error, Equatable, LocalizedError {
    case httpStatus(Int)
    case invalidImage
    case tooLarge
    case unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case .httpStatus: "The artwork service is unavailable. Try again later."
        case .invalidImage: "The artwork service returned an unreadable image."
        case .tooLarge: "The artwork service returned an image that is too large."
        case .unexpectedResponse: "The artwork service returned an unexpected response."
        }
    }
}

public struct URLSessionArtworkHTTPClient: ArtworkHTTPClient {
    private let configuration: @Sendable () -> URLSessionConfiguration

    public init(configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) {
        self.configuration = configuration
    }

    public func image(at url: URL, maximumBytes: Int64) async throws -> Data? {
        guard url.scheme == "https" else { throw ArtworkDownloadError.unexpectedResponse }
        guard maximumBytes > 0 else { throw ArtworkDownloadError.tooLarge }
        let config = configuration()
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        let transfer = ArtworkTransfer(configuration: config, maximumBytes: maximumBytes)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { transfer.start(url: url, continuation: $0) }
        } onCancel: {
            transfer.cancel()
        }
    }
}

/// URLSession delegates arrive on their own queue; cancellation can arrive on any executor.
/// The lock protects both the bounded buffer and the continuation's single completion.
private final class ArtworkTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let maximumBytes: Int64
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, any Error>?
    private var session: URLSession?
    private var data = Data()
    private var receivedImageResponse = false
    private var canceled = false

    init(configuration: URLSessionConfiguration, maximumBytes: Int64) {
        self.configuration = configuration
        self.maximumBytes = maximumBytes
    }

    func start(url: URL, continuation: CheckedContinuation<Data?, any Error>) {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: url)
        let canceled = lock.withLock {
            self.continuation = continuation
            self.session = session
            return self.canceled
        }
        if canceled { finish(.failure(CancellationError())) }
        else { task.resume() }
    }

    func cancel() {
        lock.withLock { canceled = true }
        finish(.failure(CancellationError()))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(ArtworkDownloadError.unexpectedResponse))
            return
        }
        if response.statusCode == 404 {
            completionHandler(.cancel)
            finish(.success(nil))
            return
        }
        let error: ArtworkDownloadError?
        if response.statusCode != 200 { error = .httpStatus(response.statusCode) }
        else if let type = response.mimeType, type.lowercased() != "image/png" { error = .invalidImage }
        else if response.expectedContentLength > maximumBytes { error = .tooLarge }
        else { error = nil }
        if let error {
            completionHandler(.cancel)
            finish(.failure(error))
        } else {
            // A proxy-backed session can report CONNECT headers before the image response.
            // Body bytes still require a response that explicitly declares PNG content.
            lock.withLock { receivedImageResponse = response.mimeType?.lowercased() == "image/png" }
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let error = lock.withLock { () -> ArtworkDownloadError? in
            guard continuation != nil else { return nil }
            guard receivedImageResponse else { return .invalidImage }
            guard Int64(chunk.count) <= maximumBytes - Int64(data.count) else { return .tooLarge }
            data.append(chunk)
            return nil
        }
        if let error { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(error)) }
        else {
            let result = lock.withLock { () -> Result<Data?, any Error> in
                receivedImageResponse ? .success(data) : .failure(ArtworkDownloadError.invalidImage)
            }
            finish(result)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(ArtworkDownloadError.unexpectedResponse))
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        lock.withLock { self.session = nil }
    }

    private func finish(_ result: Result<Data?, any Error>) {
        let pending = lock.withLock { () -> (CheckedContinuation<Data?, any Error>, URLSession?)? in
            guard let continuation else { return nil }
            let session = self.session
            self.continuation = nil
            data = Data()
            return (continuation, session)
        }
        guard let (continuation, session) = pending else { return }
        session?.invalidateAndCancel()
        continuation.resume(with: result)
    }
}
