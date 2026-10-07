import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB

extension GRDBBuildRepository {
    public func fetchSaveDeclarations(buildID: UUID) throws -> [BuildSaveDeclaration] {
        try read { db in
            let id = PersistenceCodec.uuid(buildID)
            return try Row.fetchAll(
                db,
                sql: """
                SELECT declaration.* FROM build_save_declarations declaration
                JOIN builds first ON first.id = declaration.first_build_id
                JOIN builds second ON second.id = declaration.second_build_id
                WHERE (first.id = ? OR second.id = ?) AND first.deletion_id IS NULL AND second.deletion_id IS NULL
                ORDER BY declaration.first_build_id, declaration.second_build_id
                """,
                arguments: [id, id]
            ).map { row in
                let value: String = row["compatibility"]
                guard let compatibility = BuildSaveCompatibility(rawValue: value) else {
                    throw PersistenceError.invalidEnum(type: "BuildSaveCompatibility", value: value)
                }
                return BuildSaveDeclaration(
                    between: try PersistenceCodec.uuid(row["first_build_id"] as String),
                    and: try PersistenceCodec.uuid(row["second_build_id"] as String), compatibility: compatibility
                )
            }
        }
    }

    public func setSaveCompatibility(between first: UUID, and second: UUID, compatibility: BuildSaveCompatibility) throws {
        guard first != second else { throw SaveDeclarationError.sameBuild }
        let declaration = BuildSaveDeclaration(between: first, and: second, compatibility: compatibility)
        try write { db in
            func gameID(of buildID: UUID) throws -> String {
                guard let gameID = try String.fetchOne(
                    db, sql: "SELECT game_id FROM builds WHERE id = ? AND deletion_id IS NULL",
                    arguments: [PersistenceCodec.uuid(buildID)]
                ) else { throw BuildOperationError.buildNotFound(buildID) }
                return gameID
            }
            guard try gameID(of: first) == gameID(of: second) else { throw SaveDeclarationError.differentGames }
            try db.execute(
                sql: """
                INSERT INTO build_save_declarations (first_build_id, second_build_id, compatibility) VALUES (?, ?, ?)
                ON CONFLICT(first_build_id, second_build_id) DO UPDATE SET compatibility = excluded.compatibility
                """,
                arguments: [PersistenceCodec.uuid(declaration.firstBuildID), PersistenceCodec.uuid(declaration.secondBuildID), compatibility.rawValue]
            )
        }
    }

    public func removeSaveCompatibility(between first: UUID, and second: UUID) throws {
        let declaration = BuildSaveDeclaration(between: first, and: second, compatibility: .sharesSaves)
        try write { db in
            try db.execute(
                sql: "DELETE FROM build_save_declarations WHERE first_build_id = ? AND second_build_id = ?",
                arguments: [PersistenceCodec.uuid(declaration.firstBuildID), PersistenceCodec.uuid(declaration.secondBuildID)]
            )
        }
    }
}
