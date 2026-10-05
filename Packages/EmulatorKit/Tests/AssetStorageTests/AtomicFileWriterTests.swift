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

    func testTheDirectoryIsSyncedAfterTheRename() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmulatorKit-AtomicWriterSyncTests-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent("battery.sav")
        let operations = RecordingFileOperations()

        try AtomicFileWriter(fileOperations: operations).write(Data([1]), to: destination)
        try AtomicFileWriter(fileOperations: operations).write(Data([2]), to: destination)

        let steps = operations.steps.filter { !$0.hasPrefix("exists") && !$0.hasPrefix("mkdir") }
        XCTAssertEqual(steps, [
            "write .tmp", "sync .tmp", "move .tmp", "syncdir \(root.lastPathComponent)",
            "write .tmp", "sync .tmp", "replace .tmp", "syncdir \(root.lastPathComponent)",
        ])
        XCTAssertEqual(try Data(contentsOf: destination), Data([2]))
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
    func synchronizeDirectory(at url: URL) throws { try live.synchronizeDirectory(at: url) }
    func moveItem(at source: URL, to destination: URL) throws { try live.moveItem(at: source, to: destination) }
    func replaceItem(at destination: URL, with source: URL) throws { throw ReplaceFailure() }
    func removeItemIfExists(at url: URL) throws { try live.removeItemIfExists(at: url) }
}

/// Performs each operation for real and records it, naming temporary files by their extension.
private final class RecordingFileOperations: FileOperations, @unchecked Sendable {
    private let live = FoundationFileOperations()
    private let lock = NSLock()
    private var recorded: [String] = []
    var steps: [String] { lock.withLock { recorded } }

    private func record(_ step: String, _ url: URL) {
        let name = url.pathExtension == "tmp" ? ".tmp" : url.lastPathComponent
        lock.withLock { recorded.append("\(step) \(name)") }
    }

    func createDirectory(at url: URL) throws { record("mkdir", url); try live.createDirectory(at: url) }
    func fileExists(at url: URL) -> Bool { record("exists", url); return live.fileExists(at: url) }
    func write(_ data: Data, to url: URL) throws { record("write", url); try live.write(data, to: url) }
    func synchronizeFile(at url: URL) throws { record("sync", url); try live.synchronizeFile(at: url) }
    func synchronizeDirectory(at url: URL) throws { record("syncdir", url); try live.synchronizeDirectory(at: url) }
    func moveItem(at source: URL, to destination: URL) throws { record("move", source); try live.moveItem(at: source, to: destination) }
    func replaceItem(at destination: URL, with source: URL) throws { record("replace", source); try live.replaceItem(at: destination, with: source) }
    func removeItemIfExists(at url: URL) throws { record("remove", url); try live.removeItemIfExists(at: url) }
}
