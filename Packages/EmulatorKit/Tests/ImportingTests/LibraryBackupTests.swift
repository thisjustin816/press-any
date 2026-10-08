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

    @Test func libraryWithROMsLargerThanTheROMZipLimitBacksUpAndRestores() throws {
        let fixture = try BackupFixture(hashing: QuickHashStore.self)
        defer { fixture.remove() }
        var library = fixture.snapshot
        let gameID = library.games[0].id
        for index in 0..<5 {
            var rom = Data(repeating: UInt8(index), count: 8 << 20)
            rom[0] = 0xff
            let url = try fixture.assetStore.sourceImageURL(sha256: fixture.assetStore.hashData(rom))
            try fixture.store.writeDataAtomically(rom, to: url)
            let asset = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: fixture.assetStore.hashData(rom),
                byteLength: Int64(rom.count), relativePath: try fixture.store.managedRelativePath(for: url),
                originalFilename: "Moon Garden \(index).gbc", integrityStatus: .verified, createdAt: fixture.date)
            library.assets.append(asset)
            library.builds.append(Build(id: UUID(), gameID: gameID, system: .gameBoyColor, displayName: "Moon Garden \(index)",
                imageAssetID: asset.id, imageSHA256: asset.contentSHA256, sourceKind: .importedImage,
                createdAt: fixture.date, modifiedAt: fixture.date))
        }
        let service = LibraryBackupService(repository: InMemoryLibraryBackupRepository(library), assetStore: fixture.assetStore)
        let summary = try service.summary(includeROMs: true)
        #expect(summary.approximateByteLength > ImportSizeLimit.archive.bytes)
        #expect(!summary.isTooLarge)
        let url = try service.export(to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1", includeROMs: true)
        #expect(try fixture.store.fileByteLength(at: url) > ImportSizeLimit.archive.bytes)
        let destinationStore = QuickHashStore(try ManagedFileStore(rootURL: fixture.root.appendingPathComponent("Destination")))
        let destination = LibraryBackupService(repository: InMemoryLibraryBackupRepository(), assetStore: destinationStore)
        let prepared = try destination.prepare(from: url)
        let report = try destination.restore(prepared, review: destination.review(prepared), choices: [:])
        #expect(report.missingROMs.isEmpty)
        for asset in library.assets where asset.kind == .sourceImage {
            #expect(try destinationStore.hashFile(at: destinationStore.managedURL(relativePath: asset.relativePath)) == asset.contentSHA256)
        }
    }

    @Test func backupOverTheSizeLimitIsRefusedBeforeAnyFileIsRead() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        var library = fixture.snapshot
        let index = try #require(library.assets.firstIndex { $0.kind == .sourceImage })
        let rom = library.assets[index]
        library.assets[index] = ManagedAsset(id: rom.id, kind: rom.kind, storageClass: rom.storageClass, contentSHA256: rom.contentSHA256,
            byteLength: LibraryBackupService.maximumArchiveBytes, relativePath: rom.relativePath, createdAt: rom.createdAt)
        let service = LibraryBackupService(repository: InMemoryLibraryBackupRepository(library), assetStore: fixture.store)
        #expect(try service.summary(includeROMs: true).isTooLarge)
        #expect(try !service.summary(includeROMs: false).isTooLarge)
        #expect {
            try service.export(to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1", includeROMs: true)
        } throws: { error in
            guard case LibraryBackupError.backupTooLarge = error else { return false }
            return error.localizedDescription.contains("Turn off Include ROMs")
        }
    }

    @Test func aSaveWrittenDuringExportIsReadAgainAndOtherwiseReportedAsSaving() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let battery = try #require(fixture.snapshot.assets.first { $0.kind == .persistentSave })
        let newBytes = Data([7, 7, 7, 7])
        try fixture.store.writeDataAtomically(newBytes, to: fixture.store.managedURL(relativePath: battery.relativePath))
        var finished = fixture.snapshot
        finished.assets[finished.assets.firstIndex { $0.id == battery.id }!] = ManagedAsset(id: battery.id, kind: battery.kind,
            storageClass: battery.storageClass, contentSHA256: fixture.store.hashData(newBytes), byteLength: Int64(newBytes.count),
            relativePath: battery.relativePath, createdAt: battery.createdAt)
        // The first read sees the old row while the file already holds the new save.
        let saving = SnapshotSequenceRepository([fixture.snapshot, finished])
        let service = LibraryBackupService(repository: saving, assetStore: fixture.store)
        let url = try service.export(to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1")
        #expect(saving.reads == 2)
        let prepared = try service.prepare(from: url)
        #expect(prepared.snapshot.assets.first { $0.id == battery.id }?.contentSHA256 == fixture.store.hashData(newBytes))

        let stuck = LibraryBackupService(repository: SnapshotSequenceRepository([fixture.snapshot]), assetStore: fixture.store)
        #expect(throws: LibraryBackupError.gameIsSaving) {
            try stuck.export(to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1")
        }
        #expect(LibraryBackupError.gameIsSaving.localizedDescription == "A game is saving. Try again in a moment.")
    }

    @Test func aChangedROMIsLeftOutAndListedLikeAMissingOne() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let rom = try #require(fixture.snapshot.assets.first { $0.kind == .sourceImage })
        try fixture.store.writeDataAtomically(Data([1]), to: fixture.store.managedURL(relativePath: rom.relativePath))
        let prepared = try fixture.service.prepare(from: fixture.export(includeROMs: true))
        #expect(!prepared.hasFile(rom.relativePath))
        #expect(prepared.manifest.notCarriedOver.contains { $0.hasPrefix("Changed ROM left out") })
    }

    @Test func theZipIsWrittenAfterTheSnapshotReadEnds() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let repository = SnapshotSequenceRepository([fixture.snapshot])
        let service = LibraryBackupService(repository: repository, assetStore: fixture.store)
        let readingWhileWriting = LockedFlag()
        _ = try service.export(to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1", includeROMs: true) { value in
            if value >= 0.6, repository.isReading { readingWhileWriting.set() }
        }
        #expect(!readingWhileWriting.value)
    }

    @Test func safetyBackupLeavesDamagedFilesOutSoReplaceStillWorks() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let state = try #require(fixture.snapshot.assets.first { $0.kind == .saveState })
        let earlier = try fixture.export()
        try fixture.store.removeIfExists(fixture.store.managedURL(relativePath: state.relativePath))
        #expect(throws: LibraryBackupError.self) { try fixture.export() }
        let prepared = try fixture.service.prepare(from: earlier)
        let review = try fixture.service.review(prepared)
        let safety = try fixture.service.makeSafetyBackup(for: prepared, review: review, to: fixture.root,
            displayName: "Test", appVersion: "1", appBuild: "1")
        let safetyBackup = try fixture.service.prepare(from: safety)
        #expect(safetyBackup.manifest.missingFiles == [state.relativePath])
        #expect(safetyBackup.manifest.notCarriedOver.contains { $0.hasPrefix("Missing file left out") })
        _ = try fixture.service.restore(prepared, review: review, choices: [:], replaceEntireLibrary: true, safetyBackupURL: safety)
    }

    @Test func aSecondQuickStateFromTheBackupIsKeptAsAManualState() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        var archive = fixture.snapshot
        archive.states[0] = archive.states[0].backupCopy(id: UUID())
        archive.states[0].kind = .quick
        archive.states[0].slot = nil
        var library = fixture.snapshot
        library.states[0].kind = .quick
        library.states[0].slot = nil
        let url = try LibraryBackupService(repository: InMemoryLibraryBackupRepository(archive), assetStore: fixture.store)
            .export(to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1")
        let repository = InMemoryLibraryBackupRepository(library)
        let service = LibraryBackupService(repository: repository, assetStore: fixture.store)
        let prepared = try service.prepare(from: url)
        _ = try service.restore(prepared, review: service.review(prepared), choices: [:])
        let states = try repository.readSnapshot { $0.states }
        #expect(states.filter { $0.kind == .quick }.map(\.id) == [library.states[0].id])
        #expect(states.contains { $0.kind == .manual && $0.label == "Quick Save from backup" })
    }

    @Test func keepingBothOfAProfileAndItsStateCopiesTheStateOnceAndCountsIt() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let prepared = try fixture.service.prepare(from: fixture.export())
        var library = fixture.snapshot
        library.profiles[0].displayName = "Jane"
        library.states[0].label = "Jane's state"
        let repository = InMemoryLibraryBackupRepository(library)
        let service = LibraryBackupService(repository: repository, assetStore: fixture.store)
        let review = try service.review(prepared)
        let choices = Dictionary(uniqueKeysWithValues: review.conflicts.map { ($0.id, RestoreChoice.keepBoth) })
        #expect(choices.count == 2)
        let report = try service.restore(prepared, review: review, choices: choices)
        let restored = try repository.readSnapshot { $0 }
        #expect(restored.profiles.count == 2)
        #expect(restored.states.count == 2)
        #expect(!restored.states.contains { $0.label?.hasSuffix("from backup") == true && $0.saveProfileID == library.profiles[0].id })
        #expect(report.added == 2)
    }

    @Test func contradictoryRecordsNameTheConflict() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        var archive = fixture.snapshot
        let rom = Data(repeating: 3, count: 64)
        let romURL = try fixture.store.sourceImageURL(sha256: fixture.store.hashData(rom))
        try fixture.store.writeDataAtomically(rom, to: romURL)
        let asset = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: fixture.store.hashData(rom),
            byteLength: Int64(rom.count), relativePath: try fixture.store.managedRelativePath(for: romURL), createdAt: fixture.date)
        archive.assets.append(asset)
        archive.builds[0].isBase = false
        archive.builds.append(Build(id: UUID(), gameID: archive.games[0].id, system: .gameBoy, displayName: "Moon Garden",
            imageAssetID: asset.id, imageSHA256: asset.contentSHA256, sourceKind: .importedImage, isBase: true,
            createdAt: fixture.date, modifiedAt: fixture.date))
        let url = try LibraryBackupService(repository: InMemoryLibraryBackupRepository(archive), assetStore: fixture.store)
            .export(to: fixture.root, displayName: "Test", appVersion: "1", appBuild: "1")
        let prepared = try fixture.service.prepare(from: url)
        let review = try fixture.service.review(prepared)
        let choices = Dictionary(uniqueKeysWithValues: review.conflicts.map { ($0.id, RestoreChoice.library) })
        #expect(throws: LibraryBackupError.conflictingChoices("Backup Game would have two Base Builds")) {
            try fixture.service.restore(prepared, review: review, choices: choices)
        }
    }

    @Test func conflictsAreNamedForPeople() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let prepared = try fixture.service.prepare(from: fixture.export())
        var library = fixture.snapshot
        library.settings[1].valueJSON = "false"
        let declaration = library.declarations[0]
        library.declarations[0] = BuildSaveDeclaration(between: declaration.firstBuildID, and: declaration.secondBuildID,
            compatibility: .doesNotShareSaves)
        let recipe = library.recipes[0]
        library.recipes[0] = PatchRecipe(id: recipe.id, resultBuildID: recipe.resultBuildID, baseBuildID: recipe.baseBuildID,
            expectedResultSHA256: recipe.expectedResultSHA256,
            items: [PatchRecipeItem(position: 0, patchAssetID: recipe.items[0].patchAssetID, enabled: false)], createdAt: recipe.createdAt)
        let service = LibraryBackupService(repository: InMemoryLibraryBackupRepository(library), assetStore: fixture.store)
        let names = Set(try service.review(prepared).conflicts.map(\.name))
        #expect(names == ["Skip boot animation (Backup Game)", "Base and Patched", "Recipe for Patched"])
    }

    @Test func gamePackagesAreNamedForTheirGameAndMayNotCarryOtherRecords() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let gameID = try #require(fixture.snapshot.games.first?.id)
        let package = try fixture.export(gameID: gameID)
        #expect(package.lastPathComponent.hasPrefix("Backup Game "))
        #expect(try fixture.export().lastPathComponent.hasPrefix("Test App Backup "))
        var entries = try ZipArchiveReader.backupEntries(in: Data(contentsOf: package))
        let index = try #require(entries.firstIndex { $0.relativePath == "settings.json" })
        let manifestIndex = try #require(entries.firstIndex { $0.relativePath == "backup-manifest.json" })
        let settings = Data(#"[{"key":"releasePreference","scopeID":"app","scopeType":"app","valueJSON":"{}"}]"#.utf8)
        entries[index] = ZipArchiveEntry(relativePath: "settings.json", data: settings)
        var manifest = try JSONDecoder().decode(LibraryBackupManifest.self, from: entries[manifestIndex].data)
        manifest.files["settings.json"] = BackupFileInfo(sha256: fixture.store.hashData(settings), byteLength: Int64(settings.count))
        manifest.recordCounts["settings"] = 1
        entries[manifestIndex] = ZipArchiveEntry(relativePath: "backup-manifest.json", data: try JSONEncoder().encode(manifest))
        let widened = fixture.root.appendingPathComponent("widened.zip")
        try ZipArchiveWriter.archive(entries: entries).write(to: widened)
        #expect(throws: LibraryBackupError.invalidArchive("the Game package holds records outside its Game")) {
            try fixture.service.prepare(from: widened)
        }
    }

    private func allFiles(_ root: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        return enumerator.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
}

/// Serves one snapshot per read, repeating the last, and records whether a read is running.
private final class SnapshotSequenceRepository: LibraryBackupRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [LibraryBackupSnapshot]
    private var readCount = 0
    private var reading = false

    init(_ snapshots: [LibraryBackupSnapshot]) { self.snapshots = snapshots }

    var reads: Int { lock.withLock { readCount } }
    var isReading: Bool { lock.withLock { reading } }

    func readSnapshot<T: Sendable>(_ operation: @Sendable (LibraryBackupSnapshot) throws -> T) throws -> T {
        let snapshot = lock.withLock {
            reading = true
            readCount += 1
            return snapshots.count > 1 ? snapshots.removeFirst() : snapshots[0]
        }
        defer { lock.withLock { reading = false } }
        return try operation(snapshot)
    }

    func commitSnapshot<T: Sendable>(replacingLibrary: Bool,
        _ operation: @Sendable (LibraryBackupSnapshot) throws -> (LibraryBackupSnapshot, RestoreReport, T)) throws -> T {
        try lock.withLock { try operation(snapshots[0]).2 }
    }

    func lastRestoreReport() throws -> RestoreReport? { nil }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set() { lock.withLock { stored = true } }
}

/// Forwards to a managed store but hashes quickly. The Linux SHA-256 fallback takes minutes for
/// the tens of megabytes a size-limit test moves; the backup logic only needs consistent hashes.
private struct QuickHashStore: AssetStore {
    let base: ManagedFileStore
    init(_ base: ManagedFileStore) { self.base = base }

    var rootURL: URL { base.rootURL }
    func stageCopy(from sourceURL: URL, transactionID: UUID) throws -> URL { try base.stageCopy(from: sourceURL, transactionID: transactionID) }
    func hashFile(at url: URL) throws -> String { hashData(try Data(contentsOf: url, options: .alwaysMapped)) }
    func hashData(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        data.withUnsafeBytes { bytes in
            for byte in bytes { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        }
        hash ^= UInt64(data.count)
        return String(repeating: String(format: "%016llx", hash), count: 4)
    }
    func sourceImageURL(sha256: String) throws -> URL { try base.sourceImageURL(sha256: sha256) }
    func sourcePatchURL(sha256: String, extension fileExtension: String) throws -> URL { try base.sourcePatchURL(sha256: sha256, extension: fileExtension) }
    func commitSourceROM(stagedURL: URL, sha256: String) throws -> URL { try base.commitSourceROM(stagedURL: stagedURL, sha256: sha256) }
    func commitSourcePatch(stagedURL: URL, sha256: String, extension fileExtension: String) throws -> URL {
        try base.commitSourcePatch(stagedURL: stagedURL, sha256: sha256, extension: fileExtension)
    }
    func variableMapURL(sha256: String, extension fileExtension: String) throws -> URL { try base.variableMapURL(sha256: sha256, extension: fileExtension) }
    func commitVariableMap(stagedURL: URL, sha256: String, extension fileExtension: String) throws -> URL {
        try base.commitVariableMap(stagedURL: stagedURL, sha256: sha256, extension: fileExtension)
    }
    func generatedImageURL(sha256: String) -> URL { base.generatedImageURL(sha256: sha256) }
    func persistentSaveURL(profileID: UUID) -> URL { base.persistentSaveURL(profileID: profileID) }
    func artworkURL(gameID: UUID, sha256: String, extension fileExtension: String) throws -> URL {
        try base.artworkURL(gameID: gameID, sha256: sha256, extension: fileExtension)
    }
    func stateURL(stateID: UUID) -> URL { base.stateURL(stateID: stateID) }
    func stateThumbnailURL(stateID: UUID, extension fileExtension: String) throws -> URL { try base.stateThumbnailURL(stateID: stateID, extension: fileExtension) }
    func quickPlayRoot(sessionID: UUID) -> URL { base.quickPlayRoot(sessionID: sessionID) }
    func quickPlaySessionIDs() throws -> [UUID] { try base.quickPlaySessionIDs() }
    func managedRelativePath(for url: URL) throws -> String { try base.managedRelativePath(for: url) }
    func managedURL(relativePath: String) throws -> URL { try base.managedURL(relativePath: relativePath) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }
    func writeDataAtomically(_ data: Data, to url: URL) throws { try base.writeDataAtomically(data, to: url) }
    func copyFileAtomically(from source: URL, to destination: URL) throws { try base.copyFileAtomically(from: source, to: destination) }
    func fileByteLength(at url: URL) throws -> Int64 { try base.fileByteLength(at: url) }
    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func removeIfExists(_ url: URL) throws { try base.removeIfExists(url) }
}

private struct BackupFixture {
    let root: URL
    let store: ManagedFileStore
    /// `store`, or a wrapper around it that the fixture's hashes come from.
    let assetStore: any AssetStore
    let snapshot: LibraryBackupSnapshot
    let repository: InMemoryLibraryBackupRepository
    let service: LibraryBackupService
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    init(hashing wrapper: QuickHashStore.Type? = nil) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try ManagedFileStore(rootURL: root.appendingPathComponent("Library"))
        assetStore = wrapper == nil ? store : QuickHashStore(store)
        let store = assetStore, date = date
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
        service = LibraryBackupService(repository: repository, assetStore: assetStore)
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
