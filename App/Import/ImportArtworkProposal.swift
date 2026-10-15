import EmulatorApplication
import Foundation

struct ImportArtworkProposal: Sendable {
    let artwork: ProvidedArtwork
    let destinationGameID: UUID?
    let preferredBuildID: UUID?
    let incomingIsPreferred: Bool
}
