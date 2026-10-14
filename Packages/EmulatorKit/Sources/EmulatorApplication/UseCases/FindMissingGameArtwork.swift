import Foundation

/// Fills empty artwork without replacing a player's choice.
public struct FindMissingGameArtwork: Sendable {
    public enum Trigger: Sendable {
        case automatic
        case userRequested
    }

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
    public func execute(gameID: UUID, lookup: ArtworkLookup, expectedPreferredBuildID: UUID? = nil,
                        trigger: Trigger = .automatic) async throws -> Bool {
        guard try isEnabled(for: trigger), let game = try games.fetchGame(id: gameID), game.artworkAssetID == nil,
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
                guard try isEnabled(for: trigger), let current = try games.fetchGame(id: gameID),
                      current.artworkAssetID == nil, current.preferredBuildID == expectedPreferredBuildID,
                      try !artwork.hasArtworkChoice(gameID: gameID) else { return false }
                try artwork.set(gameID: gameID, imageData: provided.data, fileExtension: provided.fileExtension,
                    provenance: provided.provenance)
                return true
            }
        }
        return false
    }

    private func isEnabled(for trigger: Trigger) throws -> Bool {
        switch trigger {
        case .automatic: try settings.load()
        case .userRequested: true
        }
    }
}
