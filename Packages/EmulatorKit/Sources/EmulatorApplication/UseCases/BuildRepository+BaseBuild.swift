import EmulatorDomain
import Foundation

public extension BuildRepository {
    /// A Game can have at most one Base Build. Call this in the same transaction that promotes or
    /// inserts the replacement so readers never observe two bases.
    func demoteOtherBaseBuilds(gameID: UUID, keeping buildID: UUID?, modifiedAt: Date) throws {
        for var build in try fetchBuilds(gameID: gameID)
        where build.isBase && build.id != buildID {
            build.isBase = false
            build.modifiedAt = modifiedAt
            try updateBuildMetadata(build)
        }
    }
}
