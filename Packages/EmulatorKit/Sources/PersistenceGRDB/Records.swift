import EmulatorDomain
import Foundation
import GRDB

public enum PersistenceError: Error, Equatable {
    case invalidUUID(String)
    case invalidDate(String)
    case invalidEnum(type: String, value: String)
    case invalidCorePin
    case gameHasExternalPatchDependents(Int)
}

enum PersistenceCodec {
    static func uuid(_ id: UUID) -> String { id.uuidString.lowercased() }

    static func uuid(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else { throw PersistenceError.invalidUUID(value) }
        return id
    }

    static func optionalUUID(_ value: String?) throws -> UUID? {
        guard let value else { return nil }
        return try uuid(value)
    }

    static func date(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }

    static func date(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = fractional.date(from: value) { return result }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        guard let result = standard.date(from: value) else { throw PersistenceError.invalidDate(value) }
        return result
    }

    static func optionalDate(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        return try date(value)
    }
}

struct GameRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "games"

    var id: String
    var primaryTitle: String
    var systemFamily: String
    var preferredBuildID: String?
    var preferredSaveProfileID: String?
    var createdAt: String
    var modifiedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case primaryTitle = "primary_title"
        case systemFamily = "system_family"
        case preferredBuildID = "preferred_build_id"
        case preferredSaveProfileID = "preferred_save_profile_id"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(_ value: Game) {
        id = PersistenceCodec.uuid(value.id)
        primaryTitle = value.primaryTitle
        systemFamily = value.systemFamily
        preferredBuildID = value.preferredBuildID.map(PersistenceCodec.uuid)
        preferredSaveProfileID = value.preferredSaveProfileID.map(PersistenceCodec.uuid)
        createdAt = PersistenceCodec.date(value.createdAt)
        modifiedAt = PersistenceCodec.date(value.modifiedAt)
    }

    func domain() throws -> Game {
        Game(
            id: try PersistenceCodec.uuid(id),
            primaryTitle: primaryTitle,
            systemFamily: systemFamily,
            preferredBuildID: try PersistenceCodec.optionalUUID(preferredBuildID),
            preferredSaveProfileID: try PersistenceCodec.optionalUUID(preferredSaveProfileID),
            createdAt: try PersistenceCodec.date(createdAt),
            modifiedAt: try PersistenceCodec.date(modifiedAt)
        )
    }
}

struct ManagedAssetRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "managed_assets"

    var id: String
    var kind: String
    var storageClass: String
    var contentSHA256: String
    var byteLength: Int64
    var relativePath: String
    var originalFilename: String?
    var provenanceJSON: String?
    var integrityStatus: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind
        case storageClass = "storage_class"
        case contentSHA256 = "content_sha256"
        case byteLength = "byte_length"
        case relativePath = "relative_path"
        case originalFilename = "original_filename"
        case provenanceJSON = "provenance_json"
        case integrityStatus = "integrity_status"
        case createdAt = "created_at"
    }

    init(_ value: ManagedAsset) {
        id = PersistenceCodec.uuid(value.id)
        kind = value.kind.rawValue
        storageClass = value.storageClass.rawValue
        contentSHA256 = value.contentSHA256.lowercased()
        byteLength = value.byteLength
        relativePath = value.relativePath
        originalFilename = value.originalFilename
        provenanceJSON = value.provenanceJSON
        integrityStatus = value.integrityStatus.rawValue
        createdAt = PersistenceCodec.date(value.createdAt)
    }

    func domain() throws -> ManagedAsset {
        guard let assetKind = ManagedAssetKind(rawValue: kind) else {
            throw PersistenceError.invalidEnum(type: "ManagedAssetKind", value: kind)
        }
        guard let storage = ManagedAssetStorageClass(rawValue: storageClass) else {
            throw PersistenceError.invalidEnum(type: "ManagedAssetStorageClass", value: storageClass)
        }
        guard let integrity = IntegrityStatus(rawValue: integrityStatus) else {
            throw PersistenceError.invalidEnum(type: "IntegrityStatus", value: integrityStatus)
        }
        return ManagedAsset(
            id: try PersistenceCodec.uuid(id),
            kind: assetKind,
            storageClass: storage,
            contentSHA256: contentSHA256,
            byteLength: byteLength,
            relativePath: relativePath,
            originalFilename: originalFilename,
            provenanceJSON: provenanceJSON,
            integrityStatus: integrity,
            createdAt: try PersistenceCodec.date(createdAt)
        )
    }
}

struct BuildRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "builds"

    var id: String
    var gameID: String
    var system: String
    var displayName: String
    var imageAssetID: String
    var imageSHA256: String
    var sourceKind: String
    var parentBuildID: String?
    var isBase: Bool
    var region: String?
    var language: String?
    var revision: String?
    var versionString: String?
    var versionSortKey: String?
    var preferredSaveProfileID: String?
    var pinnedCoreID: String?
    var pinnedCoreVersion: String?
    var corePinnedAt: String?
    var createdAt: String
    var modifiedAt: String

    enum CodingKeys: String, CodingKey {
        case id, system, region, language, revision
        case gameID = "game_id"
        case displayName = "display_name"
        case imageAssetID = "rom_asset_id"
        case imageSHA256 = "rom_sha256"
        case sourceKind = "source_kind"
        case parentBuildID = "parent_build_id"
        case isBase = "is_base"
        case versionString = "version_string"
        case versionSortKey = "version_sort_key"
        case preferredSaveProfileID = "preferred_save_profile_id"
        case pinnedCoreID = "pinned_core_id"
        case pinnedCoreVersion = "pinned_core_version"
        case corePinnedAt = "core_pinned_at"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(_ value: Build) {
        id = PersistenceCodec.uuid(value.id)
        gameID = PersistenceCodec.uuid(value.gameID)
        system = value.system.rawValue
        displayName = value.displayName
        imageAssetID = PersistenceCodec.uuid(value.imageAssetID)
        imageSHA256 = value.imageSHA256.lowercased()
        sourceKind = value.sourceKind.rawValue
        parentBuildID = value.parentBuildID.map(PersistenceCodec.uuid)
        isBase = value.isBase
        region = value.region
        language = value.language
        revision = value.revision
        versionString = value.versionString
        versionSortKey = value.versionSortKey
        preferredSaveProfileID = value.preferredSaveProfileID.map(PersistenceCodec.uuid)
        pinnedCoreID = value.corePin?.descriptor.identifier
        pinnedCoreVersion = value.corePin?.descriptor.version
        corePinnedAt = value.corePin.map { PersistenceCodec.date($0.pinnedAt) }
        createdAt = PersistenceCodec.date(value.createdAt)
        modifiedAt = PersistenceCodec.date(value.modifiedAt)
    }

    func domain() throws -> Build {
        guard let gameSystem = GameSystem(rawValue: system) else {
            throw PersistenceError.invalidEnum(type: "GameSystem", value: system)
        }
        guard let source = BuildSourceKind(rawValue: sourceKind) else {
            throw PersistenceError.invalidEnum(type: "BuildSourceKind", value: sourceKind)
        }
        let pin: CorePin?
        switch (pinnedCoreID, pinnedCoreVersion, corePinnedAt) {
        case (nil, nil, nil):
            pin = nil
        case let (identifier?, version?, pinnedAt?):
            pin = CorePin(
                descriptor: CoreDescriptor(identifier: identifier, version: version),
                pinnedAt: try PersistenceCodec.date(pinnedAt)
            )
        default:
            throw PersistenceError.invalidCorePin
        }
        return Build(
            id: try PersistenceCodec.uuid(id),
            gameID: try PersistenceCodec.uuid(gameID),
            system: gameSystem,
            displayName: displayName,
            imageAssetID: try PersistenceCodec.uuid(imageAssetID),
            imageSHA256: imageSHA256,
            sourceKind: source,
            parentBuildID: try PersistenceCodec.optionalUUID(parentBuildID),
            isBase: isBase,
            region: region,
            language: language,
            revision: revision,
            versionString: versionString,
            versionSortKey: versionSortKey,
            preferredSaveProfileID: try PersistenceCodec.optionalUUID(preferredSaveProfileID),
            corePin: pin,
            createdAt: try PersistenceCodec.date(createdAt),
            modifiedAt: try PersistenceCodec.date(modifiedAt)
        )
    }
}

struct SaveProfileRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "save_profiles"

    var id: String
    var gameID: String
    var displayName: String
    var badge: String?
    var persistentSaveAssetID: String?
    var copiedFromProfileID: String?
    var rtcContextJSON: String?
    var totalPlaytimeSeconds: Double
    var sessionCount: Int
    var lastPlayedAt: String?
    var createdAt: String
    var modifiedAt: String

    enum CodingKeys: String, CodingKey {
        case id, badge
        case gameID = "game_id"
        case displayName = "display_name"
        case persistentSaveAssetID = "battery_asset_id"
        case copiedFromProfileID = "copied_from_profile_id"
        case rtcContextJSON = "rtc_context_json"
        case totalPlaytimeSeconds = "total_playtime_seconds"
        case sessionCount = "session_count"
        case lastPlayedAt = "last_played_at"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(_ value: SaveProfile) {
        id = PersistenceCodec.uuid(value.id)
        gameID = PersistenceCodec.uuid(value.gameID)
        displayName = value.displayName
        badge = value.badge
        persistentSaveAssetID = value.persistentSaveAssetID.map(PersistenceCodec.uuid)
        copiedFromProfileID = value.copiedFromProfileID.map(PersistenceCodec.uuid)
        rtcContextJSON = value.rtcContextJSON
        totalPlaytimeSeconds = value.totalPlaytimeSeconds
        sessionCount = value.sessionCount
        lastPlayedAt = value.lastPlayedAt.map(PersistenceCodec.date)
        createdAt = PersistenceCodec.date(value.createdAt)
        modifiedAt = PersistenceCodec.date(value.modifiedAt)
    }

    func domain() throws -> SaveProfile {
        SaveProfile(
            id: try PersistenceCodec.uuid(id),
            gameID: try PersistenceCodec.uuid(gameID),
            displayName: displayName,
            badge: badge,
            persistentSaveAssetID: try PersistenceCodec.optionalUUID(persistentSaveAssetID),
            copiedFromProfileID: try PersistenceCodec.optionalUUID(copiedFromProfileID),
            rtcContextJSON: rtcContextJSON,
            totalPlaytimeSeconds: totalPlaytimeSeconds,
            sessionCount: sessionCount,
            lastPlayedAt: try PersistenceCodec.optionalDate(lastPlayedAt),
            createdAt: try PersistenceCodec.date(createdAt),
            modifiedAt: try PersistenceCodec.date(modifiedAt)
        )
    }
}

struct SaveStateRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "save_states"

    var id: String
    var buildID: String
    var saveProfileID: String
    var coreID: String
    var coreVersion: String
    var stateSerializationVersion: String
    var stateAssetID: String
    var screenshotAssetID: String?
    var kind: String
    var autoSequence: Int?
    var label: String?
    var playtimeSeconds: Double
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, label
        case buildID = "build_id"
        case saveProfileID = "save_profile_id"
        case coreID = "core_id"
        case coreVersion = "core_version"
        case stateSerializationVersion = "state_serialization_version"
        case stateAssetID = "state_asset_id"
        case screenshotAssetID = "screenshot_asset_id"
        case autoSequence = "auto_sequence"
        case playtimeSeconds = "playtime_seconds"
        case createdAt = "created_at"
    }

    init(_ value: SaveState) {
        id = PersistenceCodec.uuid(value.id)
        buildID = PersistenceCodec.uuid(value.buildID)
        saveProfileID = PersistenceCodec.uuid(value.saveProfileID)
        coreID = value.core.identifier
        coreVersion = value.core.version
        stateSerializationVersion = value.stateSerializationVersion
        stateAssetID = PersistenceCodec.uuid(value.stateAssetID)
        screenshotAssetID = value.screenshotAssetID.map(PersistenceCodec.uuid)
        kind = value.kind.rawValue
        autoSequence = value.autoSequence
        label = value.label
        playtimeSeconds = value.playtimeSeconds
        createdAt = PersistenceCodec.date(value.createdAt)
    }

    func domain() throws -> SaveState {
        guard let stateKind = SaveStateKind(rawValue: kind) else {
            throw PersistenceError.invalidEnum(type: "SaveStateKind", value: kind)
        }
        return SaveState(
            id: try PersistenceCodec.uuid(id),
            buildID: try PersistenceCodec.uuid(buildID),
            saveProfileID: try PersistenceCodec.uuid(saveProfileID),
            core: CoreDescriptor(identifier: coreID, version: coreVersion),
            stateSerializationVersion: stateSerializationVersion,
            stateAssetID: try PersistenceCodec.uuid(stateAssetID),
            screenshotAssetID: try PersistenceCodec.optionalUUID(screenshotAssetID),
            kind: stateKind,
            autoSequence: autoSequence,
            label: label,
            playtimeSeconds: playtimeSeconds,
            createdAt: try PersistenceCodec.date(createdAt)
        )
    }
}

struct PatchRecipeRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "patch_recipes"

    var id: String
    var resultBuildID: String
    var baseBuildID: String
    var expectedResultSHA256: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case resultBuildID = "result_build_id"
        case baseBuildID = "base_build_id"
        case expectedResultSHA256 = "expected_result_sha256"
        case createdAt = "created_at"
    }

    init(_ value: PatchRecipe) {
        id = PersistenceCodec.uuid(value.id)
        resultBuildID = PersistenceCodec.uuid(value.resultBuildID)
        baseBuildID = PersistenceCodec.uuid(value.baseBuildID)
        expectedResultSHA256 = value.expectedResultSHA256.lowercased()
        createdAt = PersistenceCodec.date(value.createdAt)
    }
}

struct PatchRecipeItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "patch_recipe_items"

    var recipeID: String
    var position: Int
    var patchAssetID: String
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case position, enabled
        case recipeID = "recipe_id"
        case patchAssetID = "patch_asset_id"
    }

    init(recipeID: UUID, value: PatchRecipeItem) {
        self.recipeID = PersistenceCodec.uuid(recipeID)
        position = value.position
        patchAssetID = PersistenceCodec.uuid(value.patchAssetID)
        enabled = value.enabled
    }

    func domain() throws -> PatchRecipeItem {
        PatchRecipeItem(
            position: position,
            patchAssetID: try PersistenceCodec.uuid(patchAssetID),
            enabled: enabled
        )
    }
}
