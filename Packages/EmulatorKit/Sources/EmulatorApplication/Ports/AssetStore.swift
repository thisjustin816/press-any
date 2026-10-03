import Foundation

public protocol AssetStore: Sendable {
    var rootURL: URL { get }

    func stageCopy(from sourceURL: URL, transactionID: UUID) throws -> URL
    func hashFile(at url: URL) throws -> String
    func hashData(_ data: Data) -> String
    func sourceImageURL(sha256: String) throws -> URL
    func sourcePatchURL(sha256: String, extension fileExtension: String) throws -> URL
    func commitSourceROM(stagedURL: URL, sha256: String) throws -> URL
    func commitSourcePatch(stagedURL: URL, sha256: String, extension fileExtension: String) throws -> URL
    func generatedImageURL(sha256: String) -> URL
    func persistentSaveURL(profileID: UUID) -> URL
    func stateURL(stateID: UUID) -> URL
    func quickPlayRoot(sessionID: UUID) -> URL
    func quickPlaySessionIDs() throws -> [UUID]
    func managedRelativePath(for url: URL) throws -> String
    func managedURL(relativePath: String) throws -> URL
    func readData(at url: URL) throws -> Data
    func writeDataAtomically(_ data: Data, to url: URL) throws
    func copyFileAtomically(from source: URL, to destination: URL) throws
    func fileByteLength(at url: URL) throws -> Int64
    func fileExists(at url: URL) -> Bool
    func removeIfExists(_ url: URL) throws
}
