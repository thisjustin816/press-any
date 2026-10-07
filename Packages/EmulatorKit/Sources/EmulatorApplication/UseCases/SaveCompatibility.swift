import EmulatorDomain
import Foundation

public enum SaveDeclarationError: Error, Equatable {
    case sameBuild
    case differentGames
}

/// Why a Save Profile's battery save may not work with a Build other than the one that wrote it.
public enum SaveCompatibilityRisk: Equatable, Sendable {
    case declaredNonShare
    case differentRegionOrLanguage(writtenRegion: String, playingRegion: String, writtenLanguage: String?, playingLanguage: String?)
    /// One of the Builds was made with GB Studio, whose builds can move saved variables around
    /// even at the same engine version.
    case gbStudio
    /// The Builds were made with different tools or tool versions, named as detected.
    case differentTools(writtenWith: [String], playingWith: [String])
    /// The cartridge headers declare different save hardware: mapper type or save RAM size.
    case differentSaveHardware
}

public struct SaveCompatibilityAssessment: Equatable, Sendable {
    /// The Build that last wrote the save, when it isn't the one about to play.
    public let writtenBy: Build?
    public let risks: [SaveCompatibilityRisk]

    public var isRisky: Bool { !risks.isEmpty }

    public static let safe = SaveCompatibilityAssessment(writtenBy: nil, risks: [])
}

/// Checks a launch's save before it plays: a save written by another Build is risky
/// according to the pair's declaration, or their detected tools, save hardware and release
/// metadata. A save with no recorded writer isn't flagged.
public struct AssessSaveCompatibility: Sendable {
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let reports: any ToolchainReportRepository
    private let images: any BuildImageResolving
    private let assetStore: any AssetStore

    public init(
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        reports: any ToolchainReportRepository,
        images: any BuildImageResolving,
        assetStore: any AssetStore
    ) {
        self.builds = builds
        self.profiles = profiles
        self.reports = reports
        self.images = images
        self.assetStore = assetStore
    }

    public func execute(context: LaunchContext) throws -> SaveCompatibilityAssessment {
        guard let profile = try profiles.fetchSaveProfile(id: context.saveProfileID),
              profile.persistentSaveAssetID != nil,
              let writerID = profile.saveWrittenByBuildID, writerID != context.buildID,
              let writer = try builds.fetchBuild(id: writerID),
              let playing = try builds.fetchBuild(id: context.buildID)
        else { return .safe }

        let declaration = try builds.fetchSaveDeclarations(buildID: writer.id)
            .first { $0.otherBuildID(than: writer.id) == playing.id }
        if declaration?.compatibility == .sharesSaves { return .safe }
        var risks: [SaveCompatibilityRisk] = declaration?.compatibility == .doesNotShareSaves ? [.declaredNonShare] : []
        if let writtenRegion = Self.recorded(writer.region), let playingRegion = Self.recorded(playing.region) {
            let writtenLanguage = Self.recorded(writer.language)
            let playingLanguage = Self.recorded(playing.language)
            let languagesDiffer = writtenLanguage != nil && playingLanguage != nil && writtenLanguage != playingLanguage
            if writtenRegion != playingRegion || languagesDiffer {
                risks.append(.differentRegionOrLanguage(
                    writtenRegion: writtenRegion, playingRegion: playingRegion,
                    writtenLanguage: writtenLanguage, playingLanguage: playingLanguage
                ))
            }
        }
        if declaration?.compatibility == .doesNotShareSaves {
            return SaveCompatibilityAssessment(writtenBy: writer, risks: risks)
        }
        let writerReports: [ToolchainDetectionReport]
        let playingReports: [ToolchainDetectionReport]
        do {
            writerReports = try reports.fetchReports(buildID: writer.id)
            playingReports = try reports.fetchReports(buildID: playing.id)
        } catch {
            guard !risks.isEmpty else { throw error }
            return SaveCompatibilityAssessment(writtenBy: writer, risks: risks)
        }
        let writerTools = Self.tools(in: writerReports)
        let playingTools = Self.tools(in: playingReports)
        if (writerTools + playingTools).contains(where: { $0.lowercased().filter(\.isLetter).hasPrefix("gbstudio") }) {
            risks.append(.gbStudio)
        } else if !writerReports.isEmpty, !playingReports.isEmpty, writerTools != playingTools {
            risks.append(.differentTools(writtenWith: writerTools, playingWith: playingTools))
        }
        // Unreadable images skip this check rather than block the launch; the launch itself
        // reports a missing image.
        if let writerHardware = saveHardware(of: writer), let playingHardware = saveHardware(of: playing),
           writerHardware != playingHardware {
            risks.append(.differentSaveHardware)
        }
        return SaveCompatibilityAssessment(writtenBy: writer, risks: risks)
    }

    /// The toolchain and engine components, as "Name Version", sorted.
    static func tools(in reports: [ToolchainDetectionReport]) -> [String] {
        reports.flatMap(\.components)
            .filter { $0.kind == .toolchain || $0.kind == .engine }
            .map { [$0.name, $0.version].compactMap { $0 }.joined(separator: " ") }
            .sorted()
    }

    private static func recorded(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The header's cartridge type and RAM size bytes, at 0x147 and 0x149.
    private func saveHardware(of build: Build) -> [UInt8]? {
        guard let url = try? images.resolveImageURL(buildID: build.id),
              let image = try? assetStore.readData(at: url), image.count > 0x149
        else { return nil }
        return [image[image.startIndex + 0x147], image[image.startIndex + 0x149]]
    }
}

/// Chooses a save for a risky launch: a copy, a blank save, or a declared share of the current
/// profile. A copy or blank save becomes the Build's default profile.
public struct ChooseSaveForBuild: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.games = games
        self.builds = builds
        self.profiles = profiles
        self.assets = assets
        self.assetStore = assetStore
        self.now = now
        self.makeID = makeID
    }

    /// Copies the launch's save into a new profile for the Build; the original isn't touched.
    public func playWithCopy(_ context: LaunchContext) throws -> LaunchContext {
        let (build, profile) = try fetch(context)
        let copy = try DuplicateSaveProfile(profiles: profiles, assets: assets, assetStore: assetStore, now: now, makeID: makeID)
            .execute(sourceProfileID: profile.id, name: "\(profile.displayName) for \(build.displayName)")
        return try makeDefault(copy, for: build)
    }

    public func playWithNewSave(_ context: LaunchContext) throws -> LaunchContext {
        let (build, _) = try fetch(context)
        let blank = try CreateBlankSaveProfile(games: games, profiles: profiles, now: now, makeID: makeID)
            .execute(gameID: build.gameID, name: build.displayName)
        return try makeDefault(blank, for: build)
    }

    public func playSharingSaves(_ context: LaunchContext, writtenByBuildID: UUID) throws -> LaunchContext {
        _ = try fetch(context)
        try builds.setSaveCompatibility(between: context.buildID, and: writtenByBuildID, compatibility: .sharesSaves)
        return context
    }

    private func fetch(_ context: LaunchContext) throws -> (Build, SaveProfile) {
        guard let build = try builds.fetchBuild(id: context.buildID) else {
            throw BuildOperationError.buildNotFound(context.buildID)
        }
        guard let profile = try profiles.fetchSaveProfile(id: context.saveProfileID) else {
            throw SaveProfileOperationError.sourceProfileNotFound(context.saveProfileID)
        }
        return (build, profile)
    }

    private func makeDefault(_ profile: SaveProfile, for build: Build) throws -> LaunchContext {
        var updated = build
        updated.preferredSaveProfileID = profile.id
        updated.modifiedAt = now()
        try builds.updateBuildMetadata(updated)
        return LaunchContext(gameID: build.gameID, buildID: build.id, saveProfileID: profile.id)
    }
}
