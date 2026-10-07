import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB
@testable import PersistenceGRDB
import Testing

@Suite("Build image SHA-1 in GRDB")
struct ImageSHA1Tests {
    @Test("a library from before SHA-1 keeps every Build, with none filled yet")
    func upgrade() throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "v1-v7-recently-deleted")
        let repositories = database.makeRepositories()
        let fixture = try legacyFixture(in: database)

        try database.migrate()

        #expect(try repositories.builds.fetchBuild(id: fixture.build.id) == fixture.build)
        #expect(try repositories.builds.fetchBuild(id: fixture.build.id)?.imageSHA1 == nil)
        // Only imported Builds are filled; a patched Build has no source file of its own.
        #expect(try repositories.builds.fetchImportedBuildsMissingImageSHA1().map(\.id) == [fixture.build.id])
    }

    @Test("a filled SHA-1 is stored, found by family lookups, and survives metadata edits")
    func fillAndFind() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let sha1 = String(repeating: "c", count: 40)
        // Read before the fill, edited after it.
        var stale = try #require(try repositories.builds.fetchBuild(id: fixture.build.id))

        try repositories.builds.setImageSHA1(buildID: fixture.build.id, sha1: sha1.uppercased())

        #expect(try repositories.builds.fetchBuild(id: fixture.build.id)?.imageSHA1 == sha1)
        #expect(try repositories.builds.fetchImportedBuildsMissingImageSHA1().isEmpty)
        #expect(try repositories.builds.fetchBuilds(imageSHA1s: [sha1, String(repeating: "d", count: 40)]).map(\.id) == [fixture.build.id])
        #expect(try repositories.builds.fetchBuilds(imageSHA1s: []).isEmpty)

        var renamed = try #require(try repositories.builds.fetchBuild(id: fixture.build.id))
        renamed.displayName = "Renamed"
        try repositories.builds.updateBuildMetadata(renamed)
        #expect(try repositories.builds.fetchBuild(id: fixture.build.id)?.imageSHA1 == sha1)

        stale.displayName = "Edited Before the Fill"
        try repositories.builds.updateBuildMetadata(stale)
        #expect(try repositories.builds.fetchBuild(id: fixture.build.id)?.imageSHA1 == sha1, "a stale edit leaves the SHA-1")
    }

    @Test("a deleted Build is left out of family lookups")
    func deletedBuildsAreNotFamily() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let sha1 = String(repeating: "e", count: 40)
        try repositories.builds.setImageSHA1(buildID: fixture.build.id, sha1: sha1)

        try repositories.deletions.insertDeletion(LibraryDeletion(
            id: UUID(), kind: .build, title: "Base", gameID: fixture.game.id, deletedAt: Date(),
            records: LibraryRecordSet(buildIDs: [fixture.build.id], saveStateIDs: [fixture.state.id])
        ))

        #expect(try repositories.builds.fetchBuilds(imageSHA1s: [sha1]).isEmpty)
    }
}
