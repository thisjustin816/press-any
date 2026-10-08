import EmulatorApplication
import Foundation

public final class InMemoryLibraryBackupRepository: LibraryBackupRepository, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var snapshot: LibraryBackupSnapshot
    private var report: RestoreReport?
    private var shouldFailCommit = false
    public var failCommit: Bool {
        get { lock.withLock { shouldFailCommit } }
        set { lock.withLock { shouldFailCommit = newValue } }
    }

    public init(_ snapshot: LibraryBackupSnapshot = LibraryBackupSnapshot()) {
        self.snapshot = snapshot
    }

    public func readSnapshot<T: Sendable>(_ operation: @Sendable (LibraryBackupSnapshot) throws -> T) throws -> T {
        try lock.withLock { try operation(snapshot) }
    }

    public func commitSnapshot<T: Sendable>(replacingLibrary: Bool,
        _ operation: @Sendable (LibraryBackupSnapshot) throws -> (LibraryBackupSnapshot, RestoreReport, T)
    ) throws -> T {
        try lock.withLock {
            let (next, nextReport, result) = try operation(snapshot)
            if shouldFailCommit { throw InMemoryBackupError.failedCommit }
            snapshot = next
            report = nextReport
            return result
        }
    }

    public func lastRestoreReport() throws -> RestoreReport? { lock.withLock { report } }
}

public enum InMemoryBackupError: LocalizedError {
    case failedCommit

    public var errorDescription: String? { "The test library failed to save the restore." }
}
