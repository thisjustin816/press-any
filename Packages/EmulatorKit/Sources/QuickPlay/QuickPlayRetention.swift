import EmulatorApplication
import Foundation

public struct QuickPlayRetention: Sendable {
    private let assetStore: any AssetStore
    private let now: @Sendable () -> Date

    public init(
        assetStore: any AssetStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.assetStore = assetStore
        self.now = now
    }

    @discardableResult
    public func removeExpiredSessions() throws -> [UUID] {
        var removed: [UUID] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        for id in try assetStore.quickPlaySessionIDs() {
            let root = assetStore.quickPlayRoot(sessionID: id)
            let manifestURL = root.appendingPathComponent("session.json")
            guard assetStore.fileExists(at: manifestURL),
                  let data = try? assetStore.readData(at: manifestURL),
                  let session = try? decoder.decode(QuickPlaySession.self, from: data) else {
                continue
            }
            if session.expiresAt <= now() {
                try assetStore.removeIfExists(root)
                removed.append(id)
            }
        }
        return removed
    }
}
