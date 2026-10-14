import Foundation

/// Fills empty artwork without delaying ROM import or replacing a player's choice.
public struct AutomaticGameArtwork: Sendable {
    private let games: any GameRepository
    private let artwork: GameArtwork
    private let settings: AutomaticArtworkSetting
    private let providers: [any ArtworkProvider]
    private let transactions: any LibraryTransactionRunner

    public init(games: any GameRepository, artwork: GameArtwork, settings: any SettingsStore,
                providers: [any ArtworkProvider], transactions: any LibraryTransactionRunner = PassthroughTransactionRunner()) {
        self.games = games
        self.artwork = artwork
        self.settings = AutomaticArtworkSetting(store: settings)
        self.providers = providers
        self.transactions = transactions
    }

    @discardableResult
    public func execute(gameID: UUID, lookup: ArtworkLookup, expectedPreferredBuildID: UUID? = nil) async throws -> Bool {
        guard try settings.load(), let game = try games.fetchGame(id: gameID), game.artworkAssetID == nil,
              game.preferredBuildID == expectedPreferredBuildID,
              try !artwork.hasArtworkChoice(gameID: gameID) else { return false }
        for provider in providers {
            try Task.checkCancellation()
            let provided: ProvidedArtwork?
            do {
                provided = try await provider.artwork(for: lookup)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                continue
            }
            guard let provided else { continue }
            try Task.checkCancellation()
            return try transactions.run {
                guard try settings.load(), let current = try games.fetchGame(id: gameID),
                      current.artworkAssetID == nil, current.preferredBuildID == expectedPreferredBuildID,
                      try !artwork.hasArtworkChoice(gameID: gameID) else { return false }
                try artwork.set(gameID: gameID, imageData: provided.data, fileExtension: provided.fileExtension,
                    provenance: provided.provenance)
                return true
            }
        }
        return false
    }
}
