import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB

public final class GRDBBuildCheatRepository: BuildCheatRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// Cheats can share a position after a restore merges two lists, so creation breaks the tie.
    static let order = "cheat.position, cheat.created_at, cheat.id"

    public func fetchCheats(buildID: UUID) throws -> [BuildCheat] {
        try read { db in
            try BuildCheatRecord.fetchAll(
                db,
                sql: """
                SELECT cheat.* FROM build_cheats cheat JOIN builds build ON build.id = cheat.build_id
                WHERE cheat.build_id = ? AND build.deletion_id IS NULL ORDER BY \(Self.order)
                """,
                arguments: [PersistenceCodec.uuid(buildID)]
            ).map { try $0.domain() }
        }
    }

    public func fetchCheat(id: UUID) throws -> BuildCheat? {
        try read { db in
            try BuildCheatRecord.fetchOne(
                db,
                sql: """
                SELECT cheat.* FROM build_cheats cheat JOIN builds build ON build.id = cheat.build_id
                WHERE cheat.id = ? AND build.deletion_id IS NULL
                """,
                arguments: [PersistenceCodec.uuid(id)]
            )?.domain()
        }
    }

    public func insertCheat(_ cheat: BuildCheat) throws {
        try write { db in
            guard try Self.buildIsLive(cheat.buildID, db: db) else { throw BuildOperationError.buildNotFound(cheat.buildID) }
            try BuildCheatRecord(cheat).insert(db)
        }
    }

    public func updateCheat(_ cheat: BuildCheat) throws {
        try write { db in
            guard try Self.buildIsLive(cheat.buildID, db: db),
                  try BuildCheatRecord.exists(db, key: PersistenceCodec.uuid(cheat.id)) else {
                throw BuildCheatError.cheatNotFound(cheat.id)
            }
            try BuildCheatRecord(cheat).update(db)
        }
    }

    public func deleteCheat(id: UUID) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM build_cheats WHERE id = ?", arguments: [PersistenceCodec.uuid(id)])
        }
    }

    private static func buildIsLive(_ buildID: UUID, db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT 1 FROM builds WHERE id = ? AND deletion_id IS NULL",
            arguments: [PersistenceCodec.uuid(buildID)]) ?? false
    }
}
