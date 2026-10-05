import EmulatorApplication
import EmulatorDomain
import Foundation

/// What Quick Play keeps beside its autosave: the core that wrote it, and the battery save file
/// as it stood when the state was taken.
struct QuickPlayAutoStateRecord: Codable, Equatable {
    var core: CoreDescriptor
    var stateSerializationVersion: String
    /// The hash of battery.sav when the state was taken, or nil when there was none.
    var batterySHA256: String?
    var playtimeSeconds: Double
}

extension QuickPlaySession {
    var autoStateURL: URL { rootURL.appendingPathComponent("autosave.state") }
    var autoStateRecordURL: URL { rootURL.appendingPathComponent("autosave.json") }

    func autoStateRecord(files: any AssetStore) -> QuickPlayAutoStateRecord? {
        guard let data = try? files.readData(at: autoStateRecordURL) else { return nil }
        return try? JSONDecoder().decode(QuickPlayAutoStateRecord.self, from: data)
    }

    func batteryHash(files: any AssetStore) -> String? {
        guard files.fileExists(at: persistentSaveURL), let data = try? files.readData(at: persistentSaveURL) else {
            return nil
        }
        return files.hashData(data)
    }

    /// Whether battery.sav was written after the autosave was taken. The state carries the
    /// cartridge RAM it was taken with, so restoring it would let the game's next save overwrite
    /// the newer one. The file's contents decide rather than its date, which is too coarse to
    /// order two writes made moments apart. An autosave without a record is trusted.
    func batteryIsNewerThanAutoState(files: any AssetStore) -> Bool {
        guard let record = autoStateRecord(files: files) else { return false }
        return batteryHash(files: files) != record.batterySHA256
    }
}
