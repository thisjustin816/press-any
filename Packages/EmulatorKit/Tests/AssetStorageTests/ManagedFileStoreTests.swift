import Foundation
import XCTest
@testable import AssetStorage

final class ManagedFileStoreTests: XCTestCase {
    func testSHA256KnownVector() throws {
        let harness = try StorageHarness.make()
        let file = try harness.write(Data("abc".utf8), named: "vector.bin")

        XCTAssertEqual(
            try harness.store.hashFile(at: file),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testSHA256LongAndEmptyVectors() throws {
        let harness = try StorageHarness.make()
        let millionA = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
        let file = try harness.write(millionA, named: "million.bin")
        let expected = "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"

        XCTAssertEqual(harness.store.hashData(millionA), expected)
        XCTAssertEqual(try harness.store.hashFile(at: file), expected)
        XCTAssertEqual(
            harness.store.hashData(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testSHA256IsIndependentOfChunkBoundaries() throws {
        let harness = try StorageHarness.make()
        for length in [1, 55, 56, 63, 64, 65, 127, 128, 1000] {
            let data = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
            let file = try harness.write(data, named: "chunks-\(length).bin")
            let whole = SHA256Digest.data(data)
            for chunkSize in [1, 7, 64, 100] {
                XCTAssertEqual(
                    try SHA256Digest.file(at: file, chunkSize: chunkSize),
                    whole,
                    "length \(length), chunk \(chunkSize)"
                )
            }
        }
    }

    func testSameROMHashMapsToSameManagedPath() throws {
        let harness = try StorageHarness.make()
        let data = Data("rom".utf8)
        let stagedA = try harness.write(data, named: "a.gb")
        let stagedB = try harness.write(data, named: "b.gb")
        let hash = try harness.store.hashFile(at: stagedA)

        let first = try harness.store.commitSourceROM(stagedURL: stagedA, sha256: hash)
        let second = try harness.store.commitSourceROM(stagedURL: stagedB, sha256: hash)

        XCTAssertEqual(first.standardizedFileURL, second.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: first), data)
    }

    func testManagedRelativePathCannotEscapeRoot() throws {
        let harness = try StorageHarness.make()

        XCTAssertThrowsError(try harness.store.resolveManagedPath("../../outside"))
        XCTAssertThrowsError(try harness.store.resolveManagedPath("/tmp/outside"))
    }

    func testCommittingAgainRepairsADamagedSourceFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("emulatorkit-repair-\(UUID().uuidString)", isDirectory: true)
        let store = try ManagedFileStore(rootURL: root)
        let source = root.appendingPathComponent("good.gb")
        try Data(repeating: 7, count: 64).write(to: source)

        let hash = try store.hashFile(at: source)
        let committed = try store.commitSourceROM(
            stagedURL: store.stageCopy(from: source, transactionID: UUID()),
            sha256: hash
        )
        try Data("damaged".utf8).write(to: committed)

        let again = try store.commitSourceROM(
            stagedURL: store.stageCopy(from: source, transactionID: UUID()),
            sha256: hash
        )
        XCTAssertEqual(again, committed)
        XCTAssertEqual(try store.hashFile(at: committed), hash)
    }

    func testSourceROMPathUsesContentAddressedLayout() throws {
        let harness = try StorageHarness.make()
        let source = try harness.write(Data([1, 2, 3]), named: "game.gb")
        let hash = try harness.store.hashFile(at: source)

        let committed = try harness.store.commitSourceROM(stagedURL: source, sha256: hash)
        let relative = committed.path.replacingOccurrences(of: harness.root.path + "/", with: "")

        XCTAssertEqual(relative, "Source/ROM/\(String(hash.prefix(2)))/\(hash).rom")
    }
}

private struct StorageHarness {
    let root: URL
    let external: URL
    let store: ManagedFileStore

    static func make() throws -> StorageHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmulatorKit-AssetStorageTests-\(UUID().uuidString)", isDirectory: true)
        let external = root.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        return StorageHarness(root: root, external: external, store: try ManagedFileStore(rootURL: root))
    }

    func write(_ data: Data, named name: String) throws -> URL {
        let url = external.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
