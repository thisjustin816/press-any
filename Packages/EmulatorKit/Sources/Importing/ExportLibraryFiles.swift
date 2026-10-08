import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity

public enum ExportLibraryFilesError: LocalizedError, Equatable {
    case buildNotFound(UUID)
    case gameNotFound(UUID)
    case saveProfileNotFound(UUID)
    /// The profile is blank: the game hasn't saved to it yet.
    case noSave(UUID)

    public var errorDescription: String? {
        switch self {
        case .buildNotFound, .gameNotFound, .saveProfileNotFound:
            "It’s no longer in the library."
        case .noSave:
            "There’s no save to export yet. The game hasn’t saved to this profile."
        }
    }
}

/// Copies a Build's ROM or a Save Profile's battery save out of the library into a folder the
/// player can reach, such as the app's Exports folder in Files. The library's own files keep their
/// content-addressed names; exports get readable ones.
public struct ExportLibraryFiles: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let images: any BuildImageResolving
    private let knownDumps: KnownDumpIndex?

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        images: any BuildImageResolving,
        knownDumps: KnownDumpIndex? = nil
    ) {
        self.games = games
        self.builds = builds
        self.profiles = profiles
        self.assets = assets
        self.assetStore = assetStore
        self.images = images
        self.knownDumps = knownDumps
    }

    /// The Build's exact ROM, rebuilt first when it's patched. A copy of a known dump takes No-Intro's
    /// name, and a hack of one takes that name with the hack after it, as in
    /// "Pokemon - Crystal Version (USA, Europe) (Rev 1) [Clear patch by Jane v2.0].gbc". Anything
    /// else is named from its metadata the same way, as Import Review suggests.
    public func exportROM(buildID: UUID, to directory: URL) throws -> URL {
        guard let build = try builds.fetchBuild(id: buildID) else {
            throw ExportLibraryFilesError.buildNotFound(buildID)
        }
        guard let game = try games.fetchGame(id: build.gameID) else {
            throw ExportLibraryFilesError.gameNotFound(build.gameID)
        }
        let source = try images.resolveImageURL(buildID: buildID)
        let metadata = BuildImportMetadata(
            region: build.region,
            language: build.language,
            revision: build.revision,
            versionString: build.versionString,
            baseTitle: build.baseTitle,
            hackTitle: build.hackTitle,
            author: build.author,
            translation: build.translation,
            status: build.status
        )
        let fileExtension = build.system.rawValue
        let name: String
        switch knownDumps?.verification(of: build, sha1: \.imageSHA1, lookup: { try? builds.fetchBuild(id: $0) }) {
        case .verified(let dump):
            name = "\(dump.name).\(fileExtension)"
        case .badDump(let dump):
            name = "\(dump.name) [b].\(fileExtension)"
        case .modified(let dump):
            let groups = FilenameMetadataParser.modificationGroups(for: metadata)
            name = "\(([dump.name] + groups).joined(separator: " ")).\(fileExtension)"
        case .unknown, nil:
            name = FilenameMetadataParser.canonicalFilename(
                fileExtension: fileExtension,
                title: game.primaryTitle,
                metadata: metadata,
                unknownGroups: []
            )
        }
        return try copy(source, named: name, into: directory)
    }

    /// The profile's battery save, named for the Game and the profile.
    public func exportSave(profileID: UUID, to directory: URL) throws -> URL {
        guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
            throw ExportLibraryFilesError.saveProfileNotFound(profileID)
        }
        guard let assetID = profile.persistentSaveAssetID, let asset = try assets.fetchAsset(id: assetID) else {
            throw ExportLibraryFilesError.noSave(profileID)
        }
        guard let game = try games.fetchGame(id: profile.gameID) else {
            throw ExportLibraryFilesError.gameNotFound(profile.gameID)
        }
        let source = try assetStore.managedURL(relativePath: asset.relativePath)
        guard assetStore.fileExists(at: source) else { throw ExportLibraryFilesError.noSave(profileID) }
        return try copy(source, named: "\(game.primaryTitle) - \(profile.displayName).sav", into: directory)
    }

    private func copy(_ source: URL, named name: String, into directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = Self.availableURL(for: Self.safeFilename(name), in: directory)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// A title can hold a slash or colon, which would name another folder or fail, and a leading
    /// dot would hide the file in Files.
    static func safeFilename(_ name: String) -> String {
        let replaced = name.map { "/\\:".contains($0) || $0.isNewline ? "-" : $0 }
        let trimmed = String(replaced).trimmingCharacters(in: .whitespaces)
        let visible = trimmed.drop { $0 == "." }
        return visible.isEmpty ? "Export" : String(visible)
    }

    /// "Name.gbc", then "Name 2.gbc" and so on, so an export never replaces an earlier one.
    static func availableURL(for name: String, in directory: URL) -> URL {
        let first = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: first.path) else { return first }
        let stem = (name as NSString).deletingPathExtension
        let fileExtension = (name as NSString).pathExtension
        var number = 2
        while true {
            let candidate = fileExtension.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(fileExtension)"
            let url = directory.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            number += 1
        }
    }
}
