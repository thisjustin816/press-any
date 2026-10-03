import Foundation
import XCTest
@testable import AssetStorage

final class AtomicFileWriterTests: XCTestCase {
    func testAtomicWriteReplacesExistingBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmulatorKit-AtomicWriterTests-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent("save/battery.sav")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: destination)

        try AtomicFileWriter().write(Data([4, 5, 6]), to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), Data([4, 5, 6]))
        XCTAssertTrue(try temporaryFiles(nextTo: destination).isEmpty)
    }

    func testReplaceFailurePreservesOriginalAndRemovesTemporaryFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmulatorKit-AtomicWriterFailureTests-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent("battery.sav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: destination)

        let operations = FailingReplaceFileOperations()
        let writer = AtomicFileWriter(fileOperations: operations)

        XCTAssertThrowsError(try writer.write(Data([9, 9, 9]), to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
        XCTAssertTrue(try temporaryFiles(nextTo: destination).isEmpty)
    }

    private func temporaryFiles(nextTo destination: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: destination.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasSuffix(".tmp") }
    }
}

private struct ReplaceFailure: Error {}

private struct FailingReplaceFileOperations: FileOperations {
    private let live = FoundationFileOperations()

    func createDirectory(at url: URL) throws { try live.createDirectory(at: url) }
    func fileExists(at url: URL) -> Bool { live.fileExists(at: url) }
    func write(_ data: Data, to url: URL) throws { try live.write(data, to: url) }
    func synchronizeFile(at url: URL) throws { try live.synchronizeFile(at: url) }
    func moveItem(at source: URL, to destination: URL) throws { try live.moveItem(at: source, to: destination) }
    func replaceItem(at destination: URL, with source: URL) throws { throw ReplaceFailure() }
    func removeItemIfExists(at url: URL) throws { try live.removeItemIfExists(at: url) }
}
