import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB
@testable import PersistenceGRDB
import Testing

@Suite("Recently Deleted in GRDB")
struct LibraryDeletionTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_500)

    private func deletion(_ fixture: Fixture, records: LibraryRecordSet, kind: LibraryDeletion.Kind = .game) -> LibraryDeletion {
        LibraryDeletion(id: UUID(), kind: kind, title: fixture.game.primaryTitle, gameID: fixture.game.id, deletedAt: now, records: records)
    }

    private func wholeGame(_ fixture: Fixture) -> LibraryRecordSet {
        LibraryRecordSet(
            gameIDs: [fixture.game.id],
            buildIDs: [fixture.build.id, fixture.patchedBuild.id],
            saveProfileIDs: [fixture.profile.id],
            saveStateIDs: [fixture.state.id]
        )
    }

    @Test("a library from before Recently Deleted keeps every row and link through the upgrade")
    func upgradeKeepsTheLibrary() throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "v1-v6-release-sort-marker")
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)

        try database.migrate()

        #expect(try repositories.games.fetchGame(id: fixture.game.id) == fixture.game)
        #expect(try repositories.builds.fetchBuilds(gameID: fixture.game.id) == [fixture.build, fixture.patchedBuild])
        #expect(try repositories.saveStates.fetchSaveStates(buildID: fixture.build.id, saveProfileID: fixture.profile.id) == [fixture.state])
        #expect(try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: fixture.patchedBuild.id) == fixture.recipe)
        let violations = try database.writer.read { db in try Row.fetchAll(db, sql: "PRAGMA foreign_key_check") }
        #expect(violations.isEmpty)
    }

    @Test("a deleted Game drops out of every read and comes back whole")
    func hideAndRestore() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let deleted = deletion(fixture, records: wholeGame(fixture))

        try repositories.deletions.insertDeletion(deleted)

        #expect(try repositories.games.fetchGames().isEmpty)
        #expect(try repositories.games.fetchGame(id: fixture.game.id) == nil)
        #expect(try repositories.builds.fetchBuild(id: fixture.build.id) == nil)
        #expect(try repositories.builds.fetchBuild(imageSHA256: fixture.build.imageSHA256) == nil)
        #expect(try repositories.saveProfiles.fetchSaveProfile(id: fixture.profile.id) == nil)
        #expect(try repositories.saveStates.fetchSaveStates(saveProfileID: fixture.profile.id).isEmpty)
        #expect(try repositories.assets.fetchAssets().count == 6, "files stay referenced while restorable")
        #expect(try repositories.deletions.fetchDeletions() == [deleted])

        try repositories.deletions.restoreDeletion(id: deleted.id)

        #expect(try repositories.games.fetchGame(id: fixture.game.id) == fixture.game)
        #expect(try repositories.builds.fetchBuilds(gameID: fixture.game.id) == [fixture.build, fixture.patchedBuild])
        #expect(try repositories.saveStates.fetchSaveStates(buildID: fixture.build.id, saveProfileID: fixture.profile.id) == [fixture.state])
        #expect(try repositories.deletions.fetchDeletions().isEmpty)
    }

    @Test("purging removes the records, leaves tombstones and releases only unused files")
    func purge() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        // Another Game still plays the same source ROM, so that file must stay.
        let other = Game(id: UUID(), primaryTitle: "Other", systemFamily: "gbc", createdAt: now, modifiedAt: now)
        try repositories.games.insertGame(other)
        var sharing = fixture.build
        sharing = Build(
            id: UUID(), gameID: other.id, system: sharing.system, displayName: "Shared",
            imageAssetID: sharing.imageAssetID, imageSHA256: sharing.imageSHA256, sourceKind: .importedImage,
            createdAt: now, modifiedAt: now
        )
        try repositories.builds.insertBuild(sharing)
        let deleted = deletion(fixture, records: wholeGame(fixture))
        try repositories.deletions.insertDeletion(deleted)

        let released = try repositories.deletions.purgeDeletion(id: deleted.id, at: now.addingTimeInterval(60))

        #expect(Set(released.map(\.id)).count == 5)
        #expect(!released.contains { $0.id == fixture.romAsset.id })
        #expect(try repositories.assets.fetchAssets().map(\.id) == [fixture.romAsset.id])
        #expect(try repositories.deletions.fetchDeletions().isEmpty)
        let tombstones = try repositories.deletions.fetchTombstones()
        #expect(Set(tombstones.map(\.recordID)) == Set(wholeGame(fixture).all.map(\.id)))
        #expect(tombstones.allSatisfy { $0.deletedAt == now && $0.purgedAt == now.addingTimeInterval(60) })
        let rows = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT (SELECT COUNT(*) FROM games) + (SELECT COUNT(*) FROM builds) + (SELECT COUNT(*) FROM save_profiles)")
        }
        #expect(rows == 2, "only the other Game and its Build remain")
    }

    @Test("a restored Base gives way to a Base made since, and the same ROM can come back meanwhile")
    func restoreAfterChanges() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let deleted = deletion(fixture, records: LibraryRecordSet(buildIDs: [fixture.build.id], saveStateIDs: [fixture.state.id]), kind: .build)
        try repositories.deletions.insertDeletion(deleted)

        var newBase = fixture.patchedBuild
        newBase.isBase = true
        try repositories.builds.updateBuildMetadata(newBase)
        try repositories.deletions.restoreDeletion(id: deleted.id)

        #expect(try repositories.builds.fetchBuild(id: fixture.build.id)?.isBase == false)
        #expect(try repositories.builds.fetchBuild(id: fixture.patchedBuild.id)?.isBase == true)

        let again = deletion(fixture, records: LibraryRecordSet(buildIDs: [fixture.build.id]), kind: .build)
        try repositories.deletions.insertDeletion(again)
        let reimported = Build(
            id: UUID(), gameID: fixture.game.id, system: fixture.build.system, displayName: "Again",
            imageAssetID: fixture.build.imageAssetID, imageSHA256: fixture.build.imageSHA256,
            sourceKind: .importedImage, createdAt: now, modifiedAt: now
        )
        try repositories.builds.insertBuild(reimported)

        #expect(throws: LibraryDeletionError.romAlreadyInGame(fixture.build.id)) {
            try repositories.deletions.restoreDeletion(id: again.id)
        }
        #expect(try repositories.builds.fetchBuild(id: fixture.build.id) == nil, "a refused restore changes nothing")
    }

    @Test("purging a base also purges a deleted patched Build that can't be rebuilt without it")
    func purgeTakesDeletedDependents() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let patched = deletion(fixture, records: LibraryRecordSet(buildIDs: [fixture.patchedBuild.id]), kind: .build)
        try repositories.deletions.insertDeletion(patched)
        let base = deletion(fixture, records: LibraryRecordSet(buildIDs: [fixture.build.id], saveStateIDs: [fixture.state.id]), kind: .build)
        try repositories.deletions.insertDeletion(base)

        _ = try repositories.deletions.purgeDeletion(id: base.id, at: now)

        #expect(try repositories.deletions.fetchDeletions().isEmpty)
        let tombstones = Set(try repositories.deletions.fetchTombstones().map(\.recordID))
        #expect(tombstones.isSuperset(of: [fixture.build.id, fixture.patchedBuild.id]))
        #expect(try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: fixture.patchedBuild.id) == nil)
    }
}
