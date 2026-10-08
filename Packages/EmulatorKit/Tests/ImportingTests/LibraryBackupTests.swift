import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Testing
@testable import Importing

@Suite struct LibraryBackupTests {
    @Test func fullLibraryRoundTripsEveryRecordAndFile() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let url = try fixture.export(includeROMs: true)
        let destination = try fixture.destination()
        let prepared = try destination.service.prepare(from: url)
        let review = try destination.service.review(prepared)
        #expect(review.conflicts.isEmpty)
        let report = try destination.service.restore(prepared, review: review, choices: [:])
        #expect(report.missingROMs.isEmpty)
        #expect(try destination.repository.readSnapshot { try BackupSnapshotCodec.canonical($0) }
                == BackupSnapshotCodec.canonical(fixture.snapshot))
        for asset in fixture.snapshot.assets where asset.kind != .generatedImage {
            #expect(try fixture.store.readData(at: fixture.store.managedURL(relativePath: asset.relativePath))
                    == destination.store.readData(at: destination.store.managedURL(relativePath: asset.relativePath)))
        }
        #expect(try destination.repository.lastRestoreReport() == report)
        #expect(prepared.manifest.migrationID == fixture.snapshot.migrationID)
    }

    @Test func identicalMergeSkipsAndNewGameIsAdded() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let prepared = try fixture.service.prepare(from: fixture.export(includeROMs: true))
        let review = try fixture.service.review(prepared)
        #expect(review.added == 0)
        #expect(review.skipped > 0)
        #expect(review.conflicts.isEmpty)
        let report = try fixture.service.restore(prepared, review: review, choices: [:])
        #expect(report.added == 0)
        var extended = fixture.snapshot
        extended.games.append(Game(id: UUID(), primaryTitle: "New Game", systemFamily: "gameboy", createdAt: fixture.date, modifiedAt: fixture.date))
        let extra = LibraryBackupService(repository: InMemoryLibraryBackupRepository(extended), assetStore: fixture.store)
        let more = try extra.prepare(from: extra.export(to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1", includeROMs: true))
        #expect(try fixture.service.review(more).added == 1)
    }

    @Test(arguments: [RestoreChoice.library, .archive, .keepBoth])
    func profileConflictChoicesPreserveBatterySaves(_ choice: RestoreChoice) throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let prepared = try fixture.service.prepare(from: fixture.export(includeROMs: true))
        var library = fixture.snapshot
        let oldAsset = try #require(library.assets.first { $0.kind == .persistentSave })
        let newBytes = Data([90, 91, 92])
        let changedAsset = ManagedAsset(id: oldAsset.id, kind: oldAsset.kind, storageClass: oldAsset.storageClass,
            contentSHA256: fixture.store.hashData(newBytes), byteLength: Int64(newBytes.count), relativePath: oldAsset.relativePath,
            originalFilename: oldAsset.originalFilename, createdAt: oldAsset.createdAt)
        library.assets[library.assets.firstIndex { $0.id == oldAsset.id }!] = changedAsset
        library.profiles[0].modifiedAt = fixture.date.addingTimeInterval(100)
        try fixture.store.writeDataAtomically(newBytes, to: fixture.store.managedURL(relativePath: oldAsset.relativePath))
        let repository = InMemoryLibraryBackupRepository(library)
        let service = LibraryBackupService(repository: repository, assetStore: fixture.store)
        let review = try service.review(prepared)
        let conflict = try #require(review.conflicts.first { $0.kind == "Save Profile" })
        #expect(conflict.requiresExplicitChoice)
        #expect(conflict.suggestedChoice == .library)
        #expect(throws: LibraryBackupError.self) { try service.restore(prepared, review: review, choices: [:]) }
        let report = try service.restore(prepared, review: review, choices: [conflict.id: choice])
        #expect(report.resolutions.count == 1)
        let restored = try repository.readSnapshot { $0 }
        let originalProfile = try #require(restored.profiles.first { $0.id == library.profiles[0].id })
        let originalAsset = try #require(restored.assets.first { $0.id == originalProfile.persistentSaveAssetID })
        let currentBytes = try fixture.store.readData(at: fixture.store.managedURL(relativePath: originalAsset.relativePath))
        #expect(currentBytes == (choice == .archive ? Data([1, 2, 3]) : newBytes))
        if choice != .library {
            let copy = try #require(restored.profiles.first { $0.id != originalProfile.id })
            #expect(copy.displayName == "Main\(choice == .archive ? " before restore" : " from backup")")
            let copyAsset = try #require(restored.assets.first { $0.id == copy.persistentSaveAssetID })
            #expect(copyAsset.relativePath != originalAsset.relativePath)
            #expect(try fixture.store.readData(at: fixture.store.managedURL(relativePath: copyAsset.relativePath))
                    == (choice == .archive ? newBytes : Data([1, 2, 3])))
        }
    }

    @Test(arguments: [RestoreChoice.library, .archive, .keepBoth])
    func stateConflictChoicesKeepReplacedState(_ choice: RestoreChoice) throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let prepared = try fixture.service.prepare(from: fixture.export(includeROMs: true))
        var library = fixture.snapshot
        library.states[0].label = "Player state"
        let repository = InMemoryLibraryBackupRepository(library)
        let service = LibraryBackupService(repository: repository, assetStore: fixture.store)
        let review = try service.review(prepared)
        let conflict = try #require(review.conflicts.first { $0.kind == "Save State" })
        _ = try service.restore(prepared, review: review, choices: [conflict.id: choice])
        let states = try repository.readSnapshot { $0.states }
        #expect(states.count == fixture.snapshot.states.count + (choice == .library ? 0 : 1))
        if choice != .library { #expect(states.contains { $0.kind == .manual && $0.label?.contains(choice == .archive ? "before restore" : "from backup") == true }) }
    }

    @Test func missingROMsRestoreWithAssetRowsAndReport() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let destination = try fixture.destination()
        let prepared = try destination.service.prepare(from: fixture.export())
        let review = try destination.service.review(prepared)
        #expect(review.missingROMs.count == 2)
        let report = try destination.service.restore(prepared, review: review, choices: [:])
        #expect(report.missingROMs.count == 2)
        let source = try #require(destination.repository.readSnapshot { $0.assets.first { $0.kind == .sourceImage } })
        #expect(!destination.store.fileExists(at: try destination.store.managedURL(relativePath: source.relativePath)))
    }

    @Test func replacementRequiresVerifiedSafetyBackupAndFailureKeepsFilesAndLibrary() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let prepared = try fixture.service.prepare(from: fixture.export(includeROMs: true))
        let review = try fixture.service.review(prepared)
        #expect(throws: LibraryBackupError.safetyBackupRequired) {
            try fixture.service.restore(prepared, review: review, choices: [:], replaceEntireLibrary: true)
        }
        let safety = try fixture.service.makeSafetyBackup(for: prepared, review: review, to: fixture.root,
            displayName: "Test", appVersion: "1", appBuild: "1")
        #expect(FileManager.default.fileExists(atPath: safety.path))
        fixture.repository.failCommit = true
        #expect(throws: InMemoryBackupError.self) {
            try fixture.service.restore(prepared, review: review, choices: [:], replaceEntireLibrary: true, safetyBackupURL: safety)
        }
        #expect(try fixture.repository.readSnapshot { $0 } == fixture.snapshot)
        let fileCount = try allFiles(fixture.store.rootURL).count
        fixture.repository.failCommit = false
        let report = try fixture.service.restore(prepared, review: review, choices: [:], replaceEntireLibrary: true, safetyBackupURL: safety)
        #expect(fixture.store.fileExists(at: safety))
        #expect(!String(decoding: try JSONEncoder().encode(report), as: UTF8.self).contains(safety.lastPathComponent))
        #expect(try allFiles(fixture.store.rootURL).count >= fileCount)
    }

    @Test func safetyBackupAlwaysCarriesROMsEvenWhenTheIncomingBackupDoesNot() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let withoutROMs = try fixture.export()
        let prepared = try fixture.service.prepare(from: withoutROMs)
        let review = try fixture.service.review(prepared)
        let safety = try fixture.service.makeSafetyBackup(for: prepared, review: review, to: fixture.root,
            displayName: "Test", appVersion: "1", appBuild: "1")
        #expect(try fixture.service.prepare(from: safety).manifest.includesROMs)
        #expect(throws: LibraryBackupError.safetyBackupRequired) {
            try fixture.service.restore(prepared, review: review, choices: [:], replaceEntireLibrary: true, safetyBackupURL: withoutROMs)
        }
        _ = try fixture.service.restore(prepared, review: review, choices: [:], replaceEntireLibrary: true, safetyBackupURL: safety)
    }

    @Test func brokenLibraryReferencesFailExportWithExportWording() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        var broken = fixture.snapshot
        broken.states[0] = SaveState(id: broken.states[0].id, buildID: UUID(), saveProfileID: broken.states[0].saveProfileID,
            core: broken.states[0].core, stateSerializationVersion: "test", stateAssetID: broken.states[0].stateAssetID,
            kind: .manual, playtimeSeconds: 0, createdAt: fixture.date)
        let service = LibraryBackupService(repository: InMemoryLibraryBackupRepository(broken), assetStore: fixture.store)
        #expect {
            try service.export(to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1")
        } throws: { error in
            guard case LibraryBackupError.cannotBackUp = error else { return false }
            return error.localizedDescription.hasPrefix("The library can't be backed up")
        }
    }

    @Test func damagedNewerAndMissingArchivesFailBeforeChanges() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let url = try fixture.export(includeROMs: true)
        let original = try ZipArchiveReader.backupEntries(in: Data(contentsOf: url))
        for mutation in 0..<3 {
            var entries = original
            if mutation == 0 {
                let index = try #require(entries.firstIndex { $0.relativePath == "games.json" })
                entries[index] = ZipArchiveEntry(relativePath: "games.json", data: Data("[]".utf8))
            } else if mutation == 1 {
                let index = try #require(entries.firstIndex { $0.relativePath == "backup-manifest.json" })
                var manifest = try JSONDecoder().decode(LibraryBackupManifest.self, from: entries[index].data)
                manifest.formatVersion = 99
                entries[index] = ZipArchiveEntry(relativePath: "backup-manifest.json", data: try JSONEncoder().encode(manifest))
            } else { entries.removeAll { $0.relativePath == "profiles.json" } }
            let damaged = fixture.root.appendingPathComponent("damaged-\(mutation).zip")
            try ZipArchiveWriter.archive(entries: entries).write(to: damaged)
            #expect(throws: LibraryBackupError.self) { try fixture.service.prepare(from: damaged) }
            #expect(try fixture.repository.readSnapshot { $0 } == fixture.snapshot)
            #expect(try fixture.repository.lastRestoreReport() == nil)
        }
    }

    @Test func gamePackageRoundTripsAndMerges() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let id = try #require(fixture.snapshot.games.first?.id)
        let destination = try fixture.destination()
        let prepared = try destination.service.prepare(from: fixture.export(includeROMs: true, gameID: id))
        #expect(prepared.manifest.isGamePackage)
        #expect(!prepared.snapshot.settings.contains { $0.scopeType == "app" })
        _ = try destination.service.restore(prepared, review: destination.service.review(prepared), choices: [:])
        #expect(try destination.service.review(prepared).conflicts.isEmpty)
        #expect(try destination.service.review(prepared).added == 0)
        #expect(throws: LibraryBackupError.self) { try destination.service.makeSafetyBackup(for: prepared,
            review: destination.service.review(prepared), to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1") }
    }

    @Test func changedLibraryAfterReviewIsRefused() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let prepared = try fixture.service.prepare(from: fixture.export())
        let review = try fixture.service.review(prepared)
        _ = try fixture.repository.commitSnapshot(replacingLibrary: false) { snapshot in
            var snapshot = snapshot
            snapshot.games[0].primaryTitle = "Changed"
            return (snapshot, RestoreReport(restoredAt: Date()), true)
        }
        #expect(throws: LibraryBackupError.libraryChanged) { try fixture.service.restore(prepared, review: review, choices: [:]) }
    }

    @Test(arguments: [RestoreChoice.library, .archive])
    func buildConflictsKeepOnlyChosenMetadata(_ choice: RestoreChoice) throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let prepared = try fixture.service.prepare(from: fixture.export())
        var current = fixture.snapshot
        current.builds[0].notes = "Library note"
        current.builds[0].modifiedAt = fixture.date.addingTimeInterval(10)
        let repository = InMemoryLibraryBackupRepository(current)
        let service = LibraryBackupService(repository: repository, assetStore: fixture.store)
        let expectedBuildID = current.builds[0].id
        let review = try service.review(prepared)
        let conflict = try #require(review.conflicts.first { $0.kind == "Build" })
        #expect(!conflict.allowsKeepBoth)
        #expect(throws: LibraryBackupError.self) { try service.restore(prepared, review: review, choices: [conflict.id: .keepBoth]) }
        _ = try service.restore(prepared, review: review, choices: [conflict.id: choice])
        #expect(try repository.readSnapshot { $0.builds.first { $0.id == expectedBuildID }?.notes } == (choice == .archive ? "My notes" : "Library note"))
    }

    @Test(arguments: [RestoreChoice.library, .archive])
    func manualPositionConflictFollowsGameChoice(_ choice: RestoreChoice) throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let prepared = try fixture.service.prepare(from: fixture.export())
        var current = fixture.snapshot
        current.manualPositions[0].position = 7
        let repository = InMemoryLibraryBackupRepository(current)
        let service = LibraryBackupService(repository: repository, assetStore: fixture.store)
        let review = try service.review(prepared)
        let conflict = try #require(review.conflicts.first { $0.kind == "Game" })
        _ = try service.restore(prepared, review: review, choices: [conflict.id: choice])
        #expect(try repository.readSnapshot { $0.manualPositions.first?.position } == (choice == .archive ? 2 : 7))
    }

    @Test func gamePackageCarriesCrossGamePatchBaseButExcludesUnrelatedGames() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        var current = fixture.snapshot
        let gameID = current.games[0].id
        let baseGame = Game(id: UUID(), primaryTitle: "Base Game", systemFamily: "gameboy", createdAt: fixture.date, modifiedAt: fixture.date)
        let unrelated = Game(id: UUID(), primaryTitle: "Unrelated", systemFamily: "gameboy", createdAt: fixture.date, modifiedAt: fixture.date)
        current.games += [baseGame, unrelated]
        current.builds[0].gameID = baseGame.id
        let service = LibraryBackupService(repository: InMemoryLibraryBackupRepository(current), assetStore: fixture.store)
        let packageURL = try service.export(to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1", includeROMs: true, gameID: gameID)
        let package = try service.prepare(from: packageURL)
        #expect(Set(package.snapshot.games.map(\.id)) == Set([gameID, baseGame.id]))
        #expect(package.snapshot.manualPositions.allSatisfy { Set([gameID, baseGame.id]).contains($0.gameID) })
        #expect(package.snapshot.builds.count == 2)
        let destination = try fixture.destination()
        _ = try destination.service.restore(package, review: destination.service.review(package), choices: [:])
        #expect(try destination.repository.readSnapshot { $0.recipes } == package.snapshot.recipes)
    }

    @Test func occupiedSlotKeepsBothStatesAndDoesNotReplaceLibrarySlot() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let prepared = try fixture.service.prepare(from: fixture.export())
        var current = fixture.snapshot
        current.states[0] = current.states[0].backupCopy(id: UUID(), label: "Library Slot")
        let repository = InMemoryLibraryBackupRepository(current)
        let service = LibraryBackupService(repository: repository, assetStore: fixture.store)
        _ = try service.restore(prepared, review: service.review(prepared), choices: [:])
        let states = try repository.readSnapshot { $0.states }
        #expect(states.filter { $0.slot == 1 }.count == 1)
        #expect(states.first { $0.slot == 1 }?.label == "Library Slot")
        #expect(states.contains { $0.kind == .manual && $0.label?.contains("from backup") == true })
    }

    @Test func missingOptionalManifestFieldsUseDefaults() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let original = try fixture.export()
        var entries = try ZipArchiveReader.backupEntries(in: Data(contentsOf: original))
        let index = try #require(entries.firstIndex { $0.relativePath == "backup-manifest.json" })
        var json = try #require(try JSONSerialization.jsonObject(with: entries[index].data) as? [String: Any])
        for key in ["appBuild", "isGamePackage", "recordCounts", "notCarriedOver"] { json.removeValue(forKey: key) }
        entries[index] = ZipArchiveEntry(relativePath: "backup-manifest.json", data: try JSONSerialization.data(withJSONObject: json))
        let url = fixture.root.appendingPathComponent("older-fields.zip")
        try ZipArchiveWriter.archive(entries: entries).write(to: url)
        let prepared = try fixture.service.prepare(from: url)
        #expect(prepared.manifest.appBuild == "")
        #expect(!prepared.manifest.isGamePackage)
        #expect(prepared.snapshot.games == fixture.snapshot.games)
    }

    private func allFiles(_ root: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        return enumerator.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
}

private struct BackupFixture {
    let root: URL
    let store: ManagedFileStore
    let snapshot: LibraryBackupSnapshot
    let repository: InMemoryLibraryBackupRepository
    let service: LibraryBackupService
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try ManagedFileStore(rootURL: root.appendingPathComponent("Library"))
        let store = store, date = date
        let gameID = UUID(), baseID = UUID(), patchedID = UUID(), profileID = UUID(), stateID = UUID()
        var value = LibraryBackupSnapshot(migrationID: "test-migration")
        func asset(kind: ManagedAssetKind, path: URL, bytes: Data, storage: ManagedAssetStorageClass = .userData) throws -> ManagedAsset {
            if kind != .generatedImage { try store.writeDataAtomically(bytes, to: path) }
            return ManagedAsset(id: UUID(), kind: kind, storageClass: storage, contentSHA256: store.hashData(bytes),
                byteLength: Int64(bytes.count), relativePath: try store.managedRelativePath(for: path),
                originalFilename: path.lastPathComponent, integrityStatus: .verified, createdAt: date)
        }
        let rom = TestROM.make(title: "BACKUP")
        let source = try asset(kind: .sourceImage, path: store.sourceImageURL(sha256: store.hashData(rom)), bytes: rom, storage: .source)
        let generated = try asset(kind: .generatedImage, path: store.generatedImageURL(sha256: store.hashData(Data([7]))), bytes: Data([7]), storage: .cache)
        let battery = try asset(kind: .persistentSave, path: store.persistentSaveURL(profileID: profileID), bytes: Data([1, 2, 3]))
        let state = try asset(kind: .saveState, path: store.stateURL(stateID: stateID), bytes: Data([4, 5]))
        let thumbnail = try asset(kind: .stateThumbnail, path: store.stateThumbnailURL(stateID: stateID, extension: "png"), bytes: Data([6]))
        let patch = try asset(kind: .sourcePatch, path: store.sourcePatchURL(sha256: store.hashData(Data([8])), extension: "ips"), bytes: Data([8]), storage: .source)
        let art = try asset(kind: .artwork, path: store.artworkURL(gameID: gameID, sha256: store.hashData(Data([9])), extension: "png"), bytes: Data([9]))
        let map = try asset(kind: .variableMap, path: store.variableMapURL(sha256: store.hashData(Data([10])), extension: "sym"), bytes: Data([10]), storage: .source)
        value.assets = [source, generated, battery, state, thumbnail, patch, art, map]
        value.games = [Game(id: gameID, primaryTitle: "Backup Game", systemFamily: "gameboy", aliases: ["Other Title"],
            hasPlayerTitle: true, isFavorite: true, preferredBuildID: patchedID, preferredSaveProfileID: profileID,
            artworkAssetID: art.id, createdAt: date, modifiedAt: date)]
        value.manualPositions = [BackupManualPosition(gameID: gameID, position: 2)]
        value.builds = [Build(id: baseID, gameID: gameID, system: .gameBoy, displayName: "Base", imageAssetID: source.id,
            imageSHA256: source.contentSHA256, sourceKind: .importedImage, isBase: true, region: "USA", language: "English",
            notes: "My notes", totalPlaytimeSeconds: 30, preferredSaveProfileID: profileID, createdAt: date, modifiedAt: date),
            Build(id: patchedID, gameID: gameID, system: .gameBoy, displayName: "Patched", imageAssetID: generated.id,
                imageSHA256: generated.contentSHA256, sourceKind: .patchRecipe, parentBuildID: baseID, createdAt: date, modifiedAt: date)]
        value.profiles = [SaveProfile(id: profileID, gameID: gameID, displayName: "Main", persistentSaveAssetID: battery.id,
            saveWrittenByBuildID: baseID, rtcContextJSON: "{}", totalPlaytimeSeconds: 30, sessionCount: 2, lastPlayedAt: date, createdAt: date, modifiedAt: date)]
        value.states = [SaveState(id: stateID, buildID: baseID, saveProfileID: profileID, core: CoreDescriptor(identifier: "sameboy", version: "1"),
            stateSerializationVersion: "test", stateAssetID: state.id, screenshotAssetID: thumbnail.id, kind: .slot, slot: 1,
            isPinned: true, playtimeSeconds: 30, createdAt: date)]
        value.recipes = [PatchRecipe(id: UUID(), resultBuildID: patchedID, baseBuildID: baseID, expectedResultSHA256: generated.contentSHA256,
            items: [PatchRecipeItem(position: 0, patchAssetID: patch.id, expectedInputSHA256: source.contentSHA256)], createdAt: date)]
        value.variableMaps = [BuildVariableMap(id: UUID(), buildID: baseID, assetID: map.id, format: .symbolFile,
            source: .userImport, originalFilename: "test.sym", attachedAt: date)]
        value.gameProvenance = [BackupProvenance(ownerID: gameID, values: [MetadataProvenance(field: .title, source: .player, providedValue: "Backup Game", recordedAt: date)])]
        value.buildProvenance = [BackupProvenance(ownerID: baseID, values: [MetadataProvenance(field: .region, source: .filename, providedValue: "USA", recordedAt: date)])]
        value.reports = [BackupToolchainReport(buildID: baseID, report: ToolchainDetectionReport(detector: "test", detectorVersion: "1", corpusRevision: "1", components: []), detectedAt: date)]
        value.declarations = [BuildSaveDeclaration(between: baseID, and: patchedID, compatibility: .sharesSaves)]
        value.settings = [BackupSetting(scopeType: "app", scopeID: "app", key: "releasePreference", valueJSON: "{}"),
            BackupSetting(scopeType: "game", scopeID: gameID.uuidString.lowercased(), key: "skipBootAnimation", valueJSON: "true")]
        snapshot = value
        repository = InMemoryLibraryBackupRepository(value)
        service = LibraryBackupService(repository: repository, assetStore: store)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
    func export(includeROMs: Bool = false, gameID: UUID? = nil) throws -> URL {
        try service.export(to: root.appendingPathComponent("Exports"), displayName: "Test App", appVersion: "1", appBuild: "2", includeROMs: includeROMs, gameID: gameID)
    }
    func destination() throws -> (store: ManagedFileStore, repository: InMemoryLibraryBackupRepository, service: LibraryBackupService) {
        let store = try ManagedFileStore(rootURL: root.appendingPathComponent(UUID().uuidString))
        let repository = InMemoryLibraryBackupRepository()
        return (store, repository, LibraryBackupService(repository: repository, assetStore: store))
    }
}
