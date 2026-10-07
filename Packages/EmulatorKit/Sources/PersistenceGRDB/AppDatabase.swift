import Foundation
import GRDB

public final class AppDatabase: @unchecked Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public convenience init(queue: DatabaseQueue) {
        self.init(writer: queue)
    }

    public convenience init(url: URL) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        // A second connection, such as another container's background SHA-1 fill on the same
        // file, waits for the lock instead of failing with "database is locked".
        configuration.busyMode = .timeout(5)
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        self.init(writer: queue)
    }

    public static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return AppDatabase(queue: try DatabaseQueue(configuration: configuration))
    }

    public func migrate() throws {
        try Self.migrator.migrate(writer)
    }

    public func makeRepositories() -> GRDBRepositorySet {
        GRDBRepositorySet(writer: writer)
    }
}
