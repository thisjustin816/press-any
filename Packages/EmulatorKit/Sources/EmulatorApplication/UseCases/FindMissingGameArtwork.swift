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
        guard let provided = try await find(gameID: gameID, lookup: lookup,
            expectedPreferredBuildID: expectedPreferredBuildID, trigger: trigger) else { return false }
        return try apply(provided, gameID: gameID, expectedPreferredBuildID: expectedPreferredBuildID, trigger: trigger)
    }

    /// Finds a proposal without saving artwork or recording a player choice.
    public func find(gameID: UUID, lookup: ArtworkLookup, expectedPreferredBuildID: UUID? = nil,
                     trigger: Trigger = .automatic) async throws -> ProvidedArtwork? {
        guard try canFill(gameID: gameID, expectedPreferredBuildID: expectedPreferredBuildID, trigger: trigger) else { return nil }
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
            guard try canFill(gameID: gameID, expectedPreferredBuildID: expectedPreferredBuildID, trigger: trigger) else { return nil }
            return provided
        }
        return nil
    }

    /// Rechecks the empty slot and player choices when a reviewed proposal is accepted.
    @discardableResult
    public func apply(_ provided: ProvidedArtwork, gameID: UUID, expectedPreferredBuildID: UUID? = nil,
                      trigger: Trigger = .automatic) throws -> Bool {
        try Task.checkCancellation()
        return try transactions.run {
            guard try canFill(gameID: gameID, expectedPreferredBuildID: expectedPreferredBuildID, trigger: trigger) else { return false }
            try artwork.set(gameID: gameID, imageData: provided.data, fileExtension: provided.fileExtension,
                provenance: provided.provenance)
            return true
        }
    }

    private func canFill(gameID: UUID, expectedPreferredBuildID: UUID?, trigger: Trigger) throws -> Bool {
        guard try isEnabled(for: trigger), let game = try games.fetchGame(id: gameID), game.artworkAssetID == nil,
              game.preferredBuildID == expectedPreferredBuildID,
              try !artwork.hasArtworkChoice(gameID: gameID) else { return false }
        return true
    }

    private func isEnabled(for trigger: Trigger) throws -> Bool {
        switch trigger {
        case .automatic: try settings.load()
        case .userRequested: true
        }
    }
}
