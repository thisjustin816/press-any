import EmulatorDomain
import Foundation

public struct QuickPlaySession: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let imageSHA256: String
    public let originalFilename: String
    public let system: GameSystem
    public let rootURL: URL
    public let startedAt: Date
    public let expiresAt: Date
    public let sourceSaveProfileID: UUID?

    public init(
        id: UUID,
        imageSHA256: String,
        originalFilename: String,
        system: GameSystem,
        rootURL: URL,
        startedAt: Date,
        expiresAt: Date,
        sourceSaveProfileID: UUID?
    ) {
        self.id = id
        self.imageSHA256 = imageSHA256
        self.originalFilename = originalFilename
        self.system = system
        self.rootURL = rootURL
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.sourceSaveProfileID = sourceSaveProfileID
    }

    public var imageURL: URL { rootURL.appendingPathComponent("rom.bin") }
    public var persistentSaveURL: URL { rootURL.appendingPathComponent("battery.sav") }
    public var manifestURL: URL { rootURL.appendingPathComponent("session.json") }

    private enum CodingKeys: String, CodingKey {
        case id
        case imageSHA256 = "romSHA256"
        case originalFilename
        case system
        case rootURL
        case startedAt
        case expiresAt
        case sourceSaveProfileID
    }
}
