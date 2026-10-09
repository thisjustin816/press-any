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
    /// The hash of the autosave this record describes. Records written before it was kept have none.
    var stateSHA256: String?
}

/// How the autosave on disk relates to the records beside it.
enum QuickPlayAutoStateMatch: Equatable {
    case described(QuickPlayAutoStateRecord)
    /// No record, as with sessions from before records were kept. The autosave is trusted.
    case unrecorded
    /// The records describe other states, so nothing is known about this one.
    case mismatched
}

extension QuickPlaySession {
    var autoStateURL: URL { rootURL.appendingPathComponent("autosave.state") }
    var autoStateRecordURL: URL { rootURL.appendingPathComponent("autosave.json") }
    /// The record of an autosave being written, kept until the state and its record are both in
    /// place. If the app stops between the two, it's the record that matches the state.
    var pendingAutoStateRecordURL: URL { rootURL.appendingPathComponent("autosave.pending.json") }

    func autoStateMatch(files: any AssetStore) -> QuickPlayAutoStateMatch {
        let record = decodedRecord(at: autoStateRecordURL, files: files)
        let pending = decodedRecord(at: pendingAutoStateRecordURL, files: files)
        guard record != nil || pending != nil else { return .unrecorded }
        let stateHash = files.fileExists(at: autoStateURL) ? try? files.hashFile(at: autoStateURL) : nil
        if let record, let stateHash, record.stateSHA256 == stateHash { return .described(record) }
        if let pending, let stateHash, pending.stateSHA256 == stateHash { return .described(pending) }
        if let record, record.stateSHA256 == nil { return .described(record) }
        return .mismatched
    }

    /// The record that describes the autosave on disk, or nil when none does.
    func autoStateRecord(files: any AssetStore) -> QuickPlayAutoStateRecord? {
        guard case .described(let record) = autoStateMatch(files: files) else { return nil }
        return record
    }

    private func decodedRecord(at url: URL, files: any AssetStore) -> QuickPlayAutoStateRecord? {
        guard let data = try? files.readData(at: url) else { return nil }
        return try? JSONDecoder().decode(QuickPlayAutoStateRecord.self, from: data)
    }

    func batteryHash(files: any AssetStore) -> String? {
        guard files.fileExists(at: persistentSaveURL), let data = try? files.readData(at: persistentSaveURL) else {
            return nil
        }
        return files.hashData(data)
    }

    /// Whether the session has an autosave that promotion would bring into the library: one with
    /// its record, taken no earlier than the battery save. A game with no battery save can still
    /// have one, and it's then the only progress the session holds.
    public func hasResumePoint(files: any AssetStore) -> Bool {
        files.fileExists(at: autoStateURL)
            && autoStateRecord(files: files) != nil
            && !autoStateIsUnsafeToRestore(files: files)
    }

    /// Whether restoring the autosave could roll back the save. It is when battery.sav was written
    /// after the autosave was taken: the state carries the cartridge RAM it was taken with, so
    /// restoring it would let the game's next save overwrite the newer one. The file's contents
    /// decide rather than its date, which is too coarse to order two writes made moments apart. An
    /// autosave without a record is trusted; one its records don't describe is not.
    func autoStateIsUnsafeToRestore(files: any AssetStore) -> Bool {
        switch autoStateMatch(files: files) {
        case .described(let record): batteryHash(files: files) != record.batterySHA256
        case .unrecorded: false
        case .mismatched: true
        }
    }
}
