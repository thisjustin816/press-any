import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GameIdentity
import XCTest

@MainActor
final class ArtworkHTTPClientTests: XCTestCase {
    func testDownloadReturnsAnImageAndTreats404AsAMiss() async throws {
        let image = try await client.image(at: url("image"), maximumBytes: 8)
        XCTAssertEqual(image, Data([1, 2, 3]))
        let missing = try await client.image(at: url("missing"), maximumBytes: 8)
        XCTAssertNil(missing)
    }

    func testServerFailureAndHTMLAreRefused() async throws {
        await assertFailure("failure", maximum: 8, expected: ArtworkDownloadError.httpStatus(503))
        await assertFailure("html", maximum: 8, expected: ArtworkDownloadError.invalidImage)
        await assertFailure("missing-type", maximum: 8, expected: ArtworkDownloadError.invalidImage)
    }

    func testProxyConnectionHeadersBeforeTheImageDoNotRejectTheDownload() async throws {
        let image = try await client.image(at: url("proxy-image"), maximumBytes: 8)
        XCTAssertEqual(image, Data([1, 2, 3]))
    }

    func testBothDeclaredAndStreamedSizesAreBounded() async throws {
        await assertFailure("declared-large", maximum: 8, expected: ArtworkDownloadError.tooLarge)
        await assertFailure("streamed-large", maximum: 8, expected: ArtworkDownloadError.tooLarge)
    }

    func testCanceledDownloadFinishesWithoutWaitingForTheServer() async throws {
        let client = client
        let task = Task { try await client.image(at: url("never-finishes"), maximumBytes: 8) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A canceled transfer must throw")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }

    private var client: URLSessionArtworkHTTPClient {
        URLSessionArtworkHTTPClient(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ArtworkURLProtocol.self]
            return configuration
        })
    }

    private func url(_ test: String) -> URL { URL(string: "https://example.com/\(test)")! }

    private func assertFailure(_ test: String, maximum: Int64, expected: ArtworkDownloadError) async {
        do {
            _ = try await client.image(at: url(test), maximumBytes: maximum)
            XCTFail("\(test) must fail")
        } catch {
            XCTAssertEqual(error as? ArtworkDownloadError, expected)
        }
    }
}

private final class ArtworkURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, url.lastPathComponent != "never-finishes" else { return }
        let status = url.lastPathComponent == "failure" ? 503 : url.lastPathComponent == "missing" ? 404 : 200
        let type = url.lastPathComponent == "html" ? "text/html" : "image/png"
        var headers = ["Content-Type": type]
        if url.lastPathComponent == "missing-type" { headers = [:] }
        if url.lastPathComponent == "proxy-image" {
            let connection = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: connection, cacheStoragePolicy: .notAllowed)
        }
        if url.lastPathComponent == "declared-large" { headers["Content-Length"] = "100" }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([1, 2, 3]))
        if url.lastPathComponent == "streamed-large" { client?.urlProtocol(self, didLoad: Data(count: 6)) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
