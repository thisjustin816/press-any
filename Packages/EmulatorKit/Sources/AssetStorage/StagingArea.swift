import Foundation

public struct StagingArea: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func transactionURL(_ transactionID: UUID) -> URL {
        rootURL.appendingPathComponent(transactionID.uuidString.lowercased(), isDirectory: true)
    }

    public func removeTransaction(_ transactionID: UUID) throws {
        let url = transactionURL(transactionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
