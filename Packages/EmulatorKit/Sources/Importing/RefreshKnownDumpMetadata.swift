import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity

public struct RefreshKnownDumpMetadata: Sendable {
    private static let versionKey = "noIntro.appliedVersion"
    private static let fields: [MetadataField] = [.region, .language, .revision, .versionString, .status]
    private let builds: any BuildRepository
    private let settings: any SettingsStore
    private let index: KnownDumpIndex
    private let transactions: any LibraryTransactionRunner
    private let now: @Sendable () -> Date

    public init(
        builds: any BuildRepository,
        settings: any SettingsStore,
        index: KnownDumpIndex,
        transactions: any LibraryTransactionRunner = PassthroughTransactionRunner(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.builds = builds
        self.settings = settings
        self.index = index
        self.transactions = transactions
        self.now = now
    }

    public func execute() throws {
        for system in index.catalog.systems {
            try transactions.run {
                let scope = SettingsScope.system(system.system)
                if let json = try settings.valueJSON(key: Self.versionKey, scope: scope),
                   try JSONDecoder().decode(String.self, from: Data(json.utf8)) == system.version { return }

                let hashes = index.catalog.games.filter { $0.system == system.system }.flatMap(\.files).map(\.sha1)
                let timestamp = now()
                // Bound queries to stay below SQLite's parameter limit for a full system catalog.
                for start in stride(from: 0, to: hashes.count, by: 500) {
                    let batch = Array(hashes[start..<min(start + 500, hashes.count)])
                    for build in try builds.fetchBuilds(imageSHA1s: batch) where build.system == system.system {
                        try refresh(build, at: timestamp)
                    }
                }
                try settings.set(system.version, key: Self.versionKey, scope: scope)
            }
        }
    }

    private func refresh(_ build: Build, at timestamp: Date) throws {
        guard let sha1 = build.imageSHA1, let dump = index.dump(sha1: sha1), dump.system == build.system else { return }
        let rows = try builds.fetchMetadataProvenance(ownerID: build.id)
        let eligible = Self.fields.filter { field in
            guard let row = rows.first(where: { $0.field == field }) else { return false }
            switch row.source {
            case .noIntro, .filename, .romHeader: return true
            case .player, .patch: return false
            }
        }
        let metadata = BuildImportMetadata(knownDump: dump)
        // A field already holding No-Intro's value keeps its row, so its recorded date stays the
        // one it was first recorded with.
        let changed = eligible.filter { field in
            let value = metadata.value(for: field)
            let row = rows.first { $0.field == field }
            return field.value(in: build) != value || row?.source != .noIntro || row?.providedValue != value
        }
        guard !changed.isEmpty else { return }
        var updated = build
        for field in changed {
            if let keyPath = field.buildMetadataKeyPath { updated[keyPath: keyPath] = metadata.value(for: field) }
        }
        if changed.contains(.versionString) { updated.versionSortKey = metadata.versionSortKey }
        updated.modifiedAt = timestamp
        try builds.updateBuildMetadata(updated)
        for field in changed {
            try builds.saveMetadataProvenance(MetadataProvenance(field: field, source: .noIntro, confidence: .high,
                providedValue: metadata.value(for: field), recordedAt: timestamp), ownerID: build.id)
        }
    }
}
