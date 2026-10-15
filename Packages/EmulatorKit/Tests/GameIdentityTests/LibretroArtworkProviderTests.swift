import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
import XCTest

@MainActor
final class LibretroArtworkProviderTests: XCTestCase {
    func testCanonicalNameIsEscapedAsOneFilenameAndReservedCharactersAreReplaced() async throws {
        let client = StubArtworkHTTPClient(results: [png])
        let provider = LibretroArtworkProvider(client: client, now: { .distantPast })
        let lookup = ArtworkLookup(system: .gameBoyColor,
            releaseNames: ["A&B: Test/Name? #100% (USA)"], inherited: true)
        let downloaded = try await provider.artwork(for: lookup)
        let result = try XCTUnwrap(downloaded)
        let urls = await client.urls
        XCTAssertEqual(urls.first?.absoluteString,
            "https://thumbnails.libretro.com/Nintendo%20-%20Game%20Boy%20Color/Named_Boxarts/A_B_%20Test_Name_%20%23100%25%20%28USA%29.png")
        XCTAssertEqual(result.data, png)
        XCTAssertEqual(result.provenance.provider, "libretro")
        XCTAssertEqual(result.provenance.sourceURL, urls.first)
        XCTAssertEqual(result.provenance.inheritedFrom, lookup.releaseNames.first)
        XCTAssertEqual(result.provenance.fetchedAt, .distantPast)
        XCTAssertFalse(result.provenance.rights.isEmpty)
    }

    func testMissingRevisionFallsBackToTheSameRegionalRelease() async throws {
        let client = StubArtworkHTTPClient(results: [nil, png])
        let provider = LibretroArtworkProvider(client: client)
        let result = try await provider.artwork(for: .init(system: .gameBoy,
            releaseNames: ["Example (World) (Rev 1)", "Example (World)"], inherited: false))
        XCTAssertNotNil(result)
        let urls = await client.urls
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.last?.lastPathComponent, "Example (World).png")
        XCTAssertNil(result?.provenance.inheritedFrom)
    }

    func testAHitStopsTheProviderAndAMissReturnsNil() async throws {
        let client = StubArtworkHTTPClient(results: [png])
        let lookup = ArtworkLookup(system: .gameBoy, releaseNames: ["Example (USA)", "Unused"], inherited: false)
        _ = try await LibretroArtworkProvider(client: client).artwork(for: lookup)
        let urls = await client.urls
        XCTAssertEqual(urls.count, 1)
        let missing = try await LibretroArtworkProvider(client: StubArtworkHTTPClient(results: [nil, nil])).artwork(for: lookup)
        XCTAssertNil(missing)
    }

    func testAnHTMLResponseIsNotArtwork() async throws {
        do {
            _ = try await LibretroArtworkProvider(client: StubArtworkHTTPClient(results: [Data("<html>error</html>".utf8)]))
                .artwork(for: .init(system: .gameBoy, releaseNames: ["Example"], inherited: false))
            XCTFail("An HTML response must be refused")
        } catch {
            XCTAssertEqual(error as? ArtworkDownloadError, .invalidImage)
        }
    }

    private var png: Data { Data([137, 80, 78, 71, 13, 10, 26, 10, 1]) }
}

private actor StubArtworkHTTPClient: ArtworkHTTPClient {
    var urls: [URL] = []
    var results: [Data?]

    init(results: [Data?]) { self.results = results }

    func image(at url: URL, maximumBytes: Int64) async throws -> Data? {
        XCTAssertEqual(maximumBytes, ImportSizeLimit.artwork.bytes)
        urls.append(url)
        return results.removeFirst()
    }
}
