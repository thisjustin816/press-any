import EmulatorApplication
import EmulatorDomain
import Foundation

public extension KnownDumpIndex {
    /// Renamed library titles and filenames never become network search terms.
    func artworkLookup(for build: Build, lookup: (UUID) -> Build?) -> ArtworkLookup? {
        let dump: KnownDump
        let inherited: Bool
        switch verification(of: build, sha1: { $0.imageSHA1 }, lookup: lookup) {
        case .verified(let match):
            guard match.system == build.system else { return nil }
            dump = match
            inherited = false
        case .modified(let match):
            dump = match
            inherited = true
        case .unknown:
            guard let reference = build.baseGameReference,
                  let name = reference.releaseName, let match = self.dump(named: name, system: reference.system) else { return nil }
            dump = match
            inherited = true
        case .badDump:
            return nil
        }
        var names = [dump.name]
        if let version = dump.version {
            let withoutVersion = dump.name.replacingOccurrences(of: " (\(version))", with: "")
            if withoutVersion != dump.name { names.append(withoutVersion) }
        }
        return ArtworkLookup(system: dump.system, releaseNames: names, inherited: inherited)
    }
}
