import EmulatorDomain
import Foundation

/// A ROM image No-Intro has verified, under its canonical name.
public struct KnownDump: Codable, Equatable, Sendable {
    /// No-Intro lists every dump's SHA-1 but only some dumps' SHA-256, so SHA-1 is the key.
    public let sha1: String
    /// The canonical name without its extension, such as "Tetris (World) (Rev 1)". The filename
    /// parser reads it like any filename for the title, region, language, revision and flags.
    public let name: String
    public let size: Int64
    public let system: GameSystem
    /// The family's parent, by name, in the same system. Nil on a parent.
    public let parent: String?
    /// Release regions as the DAT codes them, such as "USA" or "EUR".
    public let regions: [String]
    /// No-Intro knows this image to be a bad copy of the game.
    public let bad: Bool

    public init(sha1: String, name: String, size: Int64, system: GameSystem, parent: String? = nil, regions: [String] = [], bad: Bool = false) {
        self.sha1 = sha1.lowercased()
        self.name = name
        self.size = size
        self.system = system
        self.parent = parent
        self.regions = regions
        self.bad = bad
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sha1: try container.decode(String.self, forKey: .sha1),
            name: try container.decode(String.self, forKey: .name),
            size: try container.decode(Int64.self, forKey: .size),
            system: try container.decode(GameSystem.self, forKey: .system),
            parent: try container.decodeIfPresent(String.self, forKey: .parent),
            regions: try container.decodeIfPresent([String].self, forKey: .regions) ?? [],
            bad: try container.decodeIfPresent(Bool.self, forKey: .bad) ?? false
        )
    }

    /// The name before its first tag, which a family's releases share only within a region:
    /// "Pocket Monsters - Aka (Japan)" gives "Pocket Monsters - Aka".
    public var title: String {
        let end = [name.range(of: " (")?.lowerBound, name.range(of: " [")?.lowerBound].compactMap { $0 }.min()
        return end.map { String(name[..<$0]) } ?? name
    }
}

/// The bundled file: where the data came from and every known dump.
public struct KnownDumpCatalog: Codable, Equatable, Sendable {
    public struct SystemData: Codable, Equatable, Sendable {
        public let system: GameSystem
        /// The DAT's name, such as "Nintendo - Game Boy".
        public let dat: String
        /// The DAT's version, its date and time on DAT-o-MATIC. Empty before the first refresh.
        public let version: String
        public let dumps: Int

        public init(system: GameSystem, dat: String, version: String, dumps: Int) {
            self.system = system
            self.dat = dat
            self.version = version
            self.dumps = dumps
        }
    }

    public let source: String
    /// The day the file was generated, as yyyy-mm-dd.
    public let generated: String
    public let systems: [SystemData]
    public let dumps: [KnownDump]

    public init(source: String, generated: String, systems: [SystemData], dumps: [KnownDump]) {
        self.source = source
        self.generated = generated
        self.systems = systems
        self.dumps = dumps
    }
}

public enum KnownDumpError: Error, Equatable {
    case missingResource
    case unknownParent(dump: String, parent: String)
    case repeatedHash(String)
    case countMismatch(system: GameSystem, stated: Int, found: Int)
}

/// How a Build's image compares with the known dumps (`dec 18`). Nothing is ever altered to match.
public enum DumpVerification: Equatable, Sendable {
    /// The image is this dump.
    case verified(KnownDump)
    /// The image is a copy No-Intro lists as bad.
    case badDump(KnownDump)
    /// A patched Build whose chain of bases starts at this dump.
    case modified(from: KnownDump)
    case unknown
}

/// Lookups over the known dumps, by hash and by family.
public struct KnownDumpIndex: Sendable {
    private struct Key: Hashable {
        let system: GameSystem
        let name: String
    }

    public let catalog: KnownDumpCatalog
    private let bySHA1: [String: KnownDump]
    private let byName: [Key: KnownDump]
    private let clonesByParent: [Key: [KnownDump]]

    /// Checks what the generator promises: one dump per hash, every parent present, and the
    /// header's counts.
    public init(catalog: KnownDumpCatalog) throws {
        var bySHA1: [String: KnownDump] = [:]
        var byName: [Key: KnownDump] = [:]
        for dump in catalog.dumps {
            guard bySHA1.updateValue(dump, forKey: dump.sha1) == nil else { throw KnownDumpError.repeatedHash(dump.sha1) }
            byName[Key(system: dump.system, name: dump.name)] = dump
        }
        var clonesByParent: [Key: [KnownDump]] = [:]
        for dump in catalog.dumps {
            guard let parent = dump.parent else { continue }
            let key = Key(system: dump.system, name: parent)
            guard byName[key] != nil else { throw KnownDumpError.unknownParent(dump: dump.name, parent: parent) }
            clonesByParent[key, default: []].append(dump)
        }
        for system in catalog.systems {
            let found = catalog.dumps.filter { $0.system == system.system }.count
            guard found == system.dumps else {
                throw KnownDumpError.countMismatch(system: system.system, stated: system.dumps, found: found)
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

    public func dump(sha1: String) -> KnownDump? {
        bySHA1[sha1.lowercased()]
    }

    /// The parent and every clone of the dump's family, parent first, the dump itself included.
    public func family(of dump: KnownDump) -> [KnownDump] {
        let root = dump.parent.flatMap { byName[Key(system: dump.system, name: $0)] } ?? dump
        return [root] + (clonesByParent[Key(system: root.system, name: root.name)] ?? [])
    }

    /// Whether the Build is a known dump, or patched from one. A patched Build whose result is
    /// itself a known dump, as an official revision made by a patch would be, is Verified.
    /// `sha1` gives a Build's image SHA-1, nil when it isn't known; `lookup` finds each base along
    /// the chain.
    public func verification(of build: Build, sha1: (Build) -> String?, lookup: (UUID) -> Build?) -> DumpVerification {
        if let dump = sha1(build).flatMap(dump(sha1:)) { return dump.bad ? .badDump(dump) : .verified(dump) }
        var visited: Set<UUID> = [build.id]
        var current = build
        while current.sourceKind == .patchRecipe, let parentID = current.parentBuildID,
              visited.insert(parentID).inserted, let parent = lookup(parentID) {
            if let dump = sha1(parent).flatMap(dump(sha1:)), !dump.bad { return .modified(from: dump) }
            current = parent
        }
        return .unknown
    }
}
