import Foundation

/// A file that names where a Build keeps its saved variables. Kept so a later save migration can
/// match variables between Builds by name; attaching one migrates nothing.
public struct BuildVariableMap: Identifiable, Codable, Equatable, Sendable {
    public enum Format: String, Codable, Sendable {
        /// GB Studio's `game_globals.i`, or `globals.i` in older projects: `NAME = index` lines.
        case gbStudioGlobals
        /// A linker symbol file: RGBDS `.sym` (`BB:AAAA name`) or GBDK `.noi` (`DEF name 0xADDR`).
        case symbolFile
    }

    /// Where the map came from.
    public enum Source: String, Codable, Sendable {
        case userImport
    }

    public let id: UUID
    public let buildID: UUID
    public let assetID: UUID
    public let format: Format
    public let source: Source
    public let originalFilename: String
    public let attachedAt: Date

    public init(
        id: UUID,
        buildID: UUID,
        assetID: UUID,
        format: Format,
        source: Source,
        originalFilename: String,
        attachedAt: Date
    ) {
        self.id = id
        self.buildID = buildID
        self.assetID = assetID
        self.format = format
        self.source = source
        self.originalFilename = originalFilename
        self.attachedAt = attachedAt
    }
}
