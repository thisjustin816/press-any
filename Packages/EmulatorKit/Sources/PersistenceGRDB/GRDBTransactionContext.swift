import Foundation
import GRDB

private final class DatabaseContextBox: NSObject {
    let database: Database

    init(_ database: Database) {
        self.database = database
    }
}

enum GRDBTransactionContext {
    private static let key = "PersistenceGRDB.TransactionDatabase"

    static var current: Database? {
        (Thread.current.threadDictionary[key] as? DatabaseContextBox)?.database
    }

    static func withDatabase<T>(_ database: Database, operation: () throws -> T) rethrows -> T {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[key]
        dictionary[key] = DatabaseContextBox(database)
        defer {
            if let previous {
                dictionary[key] = previous
            } else {
                dictionary.removeObject(forKey: key)
            }
        }
        return try operation()
    }
}
