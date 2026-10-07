import EmulatorDomain
import Foundation

/// Finds the Game a shared battery save belongs to. Emulators name a save after its ROM, so a save
/// named like exactly one Game's ROM file picks that Game. Otherwise its title is matched the way an
/// imported ROM's is. More than one candidate is no match, so the player chooses.
public enum SaveFileMatcher {
    public static func matchingGameID(
        forSaveNamed filename: String,
        games: [Game],
        romFilenames: [(gameID: UUID, filename: String)]
    ) -> UUID? {
        let name = baseName(filename)
        let byROM = Set(romFilenames.filter { baseName($0.filename).caseInsensitiveCompare(name) == .orderedSame }.map(\.gameID))
        if byROM.count == 1 { return byROM.first }
        guard byROM.isEmpty else { return nil }
        return GameMatcher.matchingGameID(for: FilenameMetadataParser.parse(filename: filename), headerTitle: "", in: games)
    }

    private static func baseName(_ filename: String) -> String {
        ((filename.removingPercentEncoding ?? filename) as NSString).deletingPathExtension
    }
}
