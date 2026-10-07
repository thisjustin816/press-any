import EmulatorDomain
import Foundation

/// One image No-Intro lists for a game: a dump of its own or a scene release.
public struct KnownDumpFile: Codable, Equatable, Sendable {
    /// No-Intro lists every file's SHA-1 but only some files' SHA-256, so SHA-1 is the key.
    public let sha1: String
    public let size: Int64
    /// No-Intro knows this image to be a bad copy of the game.
    public let bad: Bool

    public init(sha1: String, size: Int64, bad: Bool = false) {
        self.sha1 = sha1.lowercased()
        self.size = size
        self.bad = bad
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sha1: try container.decode(String.self, forKey: .sha1),
            size: try container.decode(Int64.self, forKey: .size),
            bad: try container.decodeIfPresent(Bool.self, forKey: .bad) ?? false
        )
    }
}

/// A game as No-Intro lists it: its canonical name, the fields it records apart from the name,
/// its family, and every image known for it.
public struct KnownDump: Codable, Equatable, Sendable {
    /// The canonical name, such as "Tetris (World) (Rev 1)".
    public let name: String
    public let system: GameSystem
    /// The name without its tags, which a family's releases share only within a region.
    public let title: String
    /// As No-Intro writes them: "USA, Europe", "En,Fr,De".
    public let region: String?
    public let languages: String?
    /// The development status: "Beta", "Proto 2", "Demo". Nil for a finished release.
    public let status: String?
    /// A revision ("Rev 1") or a version ("v1.1"), as No-Intro writes it.
    public let version: String?
    /// Released after the system's commercial life, as homebrew is.
    public let aftermarket: Bool
    public let unlicensed: Bool
    /// The family's root, by name, in the same system. Nil on a root.
    public let parent: String?
    public let files: [KnownDumpFile]

    public init(
        name: String,
        system: GameSystem,
        title: String,
        region: String? = nil,
        languages: String? = nil,
        status: String? = nil,
        version: String? = nil,
        aftermarket: Bool = false,
        unlicensed: Bool = false,
        parent: String? = nil,
        files: [KnownDumpFile]
    ) {
        self.name = name
        self.system = system
        self.title = title
        self.region = region
        self.languages = languages
        self.status = status
        self.version = version
        self.aftermarket = aftermarket
        self.unlicensed = unlicensed
        self.parent = parent
        self.files = files
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            system: try container.decode(GameSystem.self, forKey: .system),
            title: try container.decode(String.self, forKey: .title),
            region: try container.decodeIfPresent(String.self, forKey: .region),
            languages: try container.decodeIfPresent(String.self, forKey: .languages),
            status: try container.decodeIfPresent(String.self, forKey: .status),
            version: try container.decodeIfPresent(String.self, forKey: .version),
            aftermarket: try container.decodeIfPresent(Bool.self, forKey: .aftermarket) ?? false,
            unlicensed: try container.decodeIfPresent(Bool.self, forKey: .unlicensed) ?? false,
            parent: try container.decodeIfPresent(String.self, forKey: .parent),
            files: try container.decode([KnownDumpFile].self, forKey: .files)
        )
    }

    public func releaseTitle(for build: Build) -> ReleaseTitle {
        ReleaseTitle(title: title, region: build.region ?? region, language: build.language ?? languages)
    }
}

/// The bundled file: where the data came from and every known game.
public struct KnownDumpCatalog: Codable, Equatable, Sendable {
    public struct SystemData: Codable, Equatable, Sendable {
        public let system: GameSystem
        /// The system's name on DAT-o-MATIC, such as "Nintendo - Game Boy".
        public let dat: String
        /// The export's version, its date and time on DAT-o-MATIC. Empty before the first refresh.
        public let version: String
        public let games: Int
        public let files: Int

        public init(system: GameSystem, dat: String, version: String, games: Int, files: Int) {
            self.system = system
            self.dat = dat
            self.version = version
            self.games = games
            self.files = files
        }
    }

    public let source: String
    /// The day the file was generated, as yyyy-mm-dd.
    public let generated: String
    public let systems: [SystemData]
    public let games: [KnownDump]

    public init(source: String, generated: String, systems: [SystemData], games: [KnownDump]) {
        self.source = source
        self.generated = generated
        self.systems = systems
        self.games = games
    }
}

public enum KnownDumpError: Error, Equatable {
    case missingResource
    case unknownParent(game: String, parent: String)
    case repeatedHash(String)
    case countMismatch(system: GameSystem, stated: Int, found: Int)
}

/// How a Build's image compares with the known dumps. Nothing is ever altered to match.
public enum DumpVerification: Equatable, Sendable {
    /// The image is a good copy of this game.
    case verified(KnownDump)
    /// The image is a copy of this game that No-Intro lists as bad.
    case badDump(KnownDump)
    /// A patched Build whose chain of bases starts at a good copy of this game.
    case modified(from: KnownDump)
    case unknown
}

/// Lookups over the known games, by file and by family.
public struct KnownDumpIndex: Sendable {
    private struct Key: Hashable {
        let system: GameSystem
        let name: String
    }

    public let catalog: KnownDumpCatalog
    private let bySHA1: [String: (game: KnownDump, file: KnownDumpFile)]
    private let byName: [Key: KnownDump]
    private let clonesByParent: [Key: [KnownDump]]

    /// Checks what the generator promises: each file in one game, every parent present, and the
    /// header's counts.
    public init(catalog: KnownDumpCatalog) throws {
        var bySHA1: [String: (game: KnownDump, file: KnownDumpFile)] = [:]
        var byName: [Key: KnownDump] = [:]
        for game in catalog.games {
            for file in game.files {
                guard bySHA1.updateValue((game, file), forKey: file.sha1) == nil else {
                    throw KnownDumpError.repeatedHash(file.sha1)
                }
            }
            byName[Key(system: game.system, name: game.name)] = game
        }
        var clonesByParent: [Key: [KnownDump]] = [:]
        for game in catalog.games {
            guard let parent = game.parent else { continue }
            let key = Key(system: game.system, name: parent)
            guard byName[key] != nil else { throw KnownDumpError.unknownParent(game: game.name, parent: parent) }
            clonesByParent[key, default: []].append(game)
        }
        for system in catalog.systems {
            let found = catalog.games.filter { $0.system == system.system }.count
            guard found == system.games else {
                throw KnownDumpError.countMismatch(system: system.system, stated: system.games, found: found)
            }
        }
        self.catalog = catalog
        self.bySHA1 = bySHA1
        self.byName = byName
        self.clonesByParent = clonesByParent.mapValues { $0.sorted { $0.name < $1.name } }
    }

    public init(data: Data) throws {
        try self.init(catalog: JSONDecoder().decode(KnownDumpCatalog.self, from: data))
    }

    /// The data that ships with the app.
    public static func bundled() throws -> KnownDumpIndex {
        guard let url = Bundle.module.url(forResource: "KnownDumps", withExtension: "json") else {
            throw KnownDumpError.missingResource
        }
        return try KnownDumpIndex(data: Data(contentsOf: url))
    }

    /// The game an image is a copy of, good or bad.
    public func dump(sha1: String) -> KnownDump? {
        bySHA1[sha1.lowercased()]?.game
    }

    /// The listed image itself, which says whether it is a bad copy.
    public func file(sha1: String) -> KnownDumpFile? {
        bySHA1[sha1.lowercased()]?.file
    }

    /// The root and every clone of the game's family, root first, the game itself included.
    public func family(of game: KnownDump) -> [KnownDump] {
        let root = game.parent.flatMap { byName[Key(system: game.system, name: $0)] } ?? game
        return [root] + (clonesByParent[Key(system: root.system, name: root.name)] ?? [])
    }

    public func reference(to dump: KnownDump, libraryGameID: UUID? = nil) -> BaseGameReference {
        BaseGameReference(title: dump.title, system: dump.system, familyName: dump.parent ?? dump.name, releaseName: dump.name, libraryGameID: libraryGameID)
    }

    public func search(_ query: String, system: GameSystem? = nil) -> [KnownDump] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return catalog.games.filter { (system == nil || $0.system == system) && $0.name.localizedStandardContains(query) }
            .sorted { $0.name < $1.name }
    }

    public func matches(_ reference: BaseGameReference, familyOf dump: KnownDump) -> Bool {
        reference.system == dump.system && reference.familyName == (dump.parent ?? dump.name)
    }

    /// Whether the Build is a known image, or patched from one. A patched Build whose result is
    /// itself known, as an official revision made by a patch would be, is Verified.
    /// `sha1` gives a Build's image SHA-1, nil when it isn't known; `lookup` finds each base along
    /// the chain.
    public func verification(of build: Build, sha1: (Build) -> String?, lookup: (UUID) -> Build?) -> DumpVerification {
        if let match = sha1(build).flatMap({ bySHA1[$0.lowercased()] }) {
            return match.file.bad ? .badDump(match.game) : .verified(match.game)
        }
        var visited: Set<UUID> = [build.id]
        var current = build
        while current.sourceKind == .patchRecipe, let parentID = current.parentBuildID,
              visited.insert(parentID).inserted, let parent = lookup(parentID) {
            if let match = sha1(parent).flatMap({ bySHA1[$0.lowercased()] }), !match.file.bad {
                return .modified(from: match.game)
            }
            current = parent
        }
        return .unknown
    }
}
