import EmulatorDomain
import Foundation

public struct LibraryDeletionTarget: Hashable, Sendable {
    public let kind: LibraryDeletion.Kind
    public let id: UUID

    public init(kind: LibraryDeletion.Kind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

public struct BatchDeletionFailure: Sendable {
    public let target: LibraryDeletionTarget
    public let title: String
    public let error: any Error
    public let reason: String
}

public struct BatchDeletionPlan: Sendable {
    public struct Item: Sendable {
        public let target: LibraryDeletionTarget
        public let plan: DeletionPlan
    }

    public let items: [Item]
    public let skipped: [BatchDeletionFailure]
    public var count: Int { items.count + skipped.count }
}

public struct BatchDeletionResult: Sendable {
    public let deleted: [LibraryDeletion]
    public let skipped: [BatchDeletionFailure]
}

public struct BatchRecoveryResult: Sendable {
    public let completed: [UUID]
    public let skipped: [BatchDeletionFailure]
}

extension LibraryDeletionOperations {
    public func planDeletion(of targets: [LibraryDeletionTarget]) -> BatchDeletionPlan {
        var items: [BatchDeletionPlan.Item] = []
        var skipped: [BatchDeletionFailure] = []
        var seen = Set<LibraryDeletionTarget>()
        for target in targets where seen.insert(target).inserted {
            do {
                items.append(.init(target: target, plan: try planDeletion(of: target)))
            } catch {
                skipped.append(failure(target, title: deletionTitle(for: target), error: error))
            }
        }
        return BatchDeletionPlan(items: items, skipped: skipped)
    }

    public func delete(_ batch: BatchDeletionPlan) -> BatchDeletionResult {
        var deleted: [LibraryDeletion] = []
        var skipped = batch.skipped
        let items = batch.items.sorted {
            if $0.target.kind != $1.target.kind {
                return deletionOrder($0.target.kind) < deletionOrder($1.target.kind)
            }
            return $0.plan.records.buildIDs.count < $1.plan.records.buildIDs.count
        }
        for item in items {
            do {
                deleted.append(try delete(planDeletion(of: item.target)))
            } catch {
                skipped.append(failure(item.target, title: item.plan.title, error: error))
            }
        }
        return BatchDeletionResult(deleted: deleted, skipped: skipped)
    }

    public func restore(deletionIDs: [UUID]) -> BatchRecoveryResult {
        recover(deletionIDs: deletionIDs, restoring: true)
    }

    public func purge(deletionIDs: [UUID]) -> BatchRecoveryResult {
        recover(deletionIDs: deletionIDs, restoring: false)
    }

    private func planDeletion(of target: LibraryDeletionTarget) throws -> DeletionPlan {
        switch target.kind {
        case .game: try planGameDeletion(gameID: target.id)
        case .build: try planBuildDeletion(buildID: target.id)
        case .saveProfile: try planProfileDeletion(profileID: target.id)
        case .saveState: try planStateDeletion(stateID: target.id)
        }
    }

    private func deletionOrder(_ kind: LibraryDeletion.Kind) -> Int {
        switch kind {
        case .saveState: 0
        case .saveProfile: 1
        case .build: 2
        case .game: 3
        }
    }

    private func recover(deletionIDs: [UUID], restoring: Bool) -> BatchRecoveryResult {
        let entries: [LibraryDeletion]
        do {
            entries = try recentlyDeleted()
        } catch {
            return BatchRecoveryResult(completed: [], skipped: deletionIDs.map {
                failure(.init(kind: .game, id: $0), error: error)
            })
        }
        var seen = Set<UUID>()
        var skipped: [BatchDeletionFailure] = []
        var pending = deletionIDs.filter { seen.insert($0).inserted }.compactMap { id -> LibraryDeletion? in
            guard let entry = entries.first(where: { $0.id == id }) else {
                skipped.append(failure(.init(kind: .game, id: id), error: LibraryDeletionError.deletionNotFound(id)))
                return nil
            }
            return entry
        }.sorted {
            let left = $0.records.gameIDs.isEmpty ? deletionOrder($0.kind) : 3
            let right = $1.records.gameIDs.isEmpty ? deletionOrder($1.kind) : 3
            return restoring ? left > right : left < right
        }
        var completed: [UUID] = []
        while !pending.isEmpty {
            var failed: [(LibraryDeletion, any Error)] = []
            let before = completed.count
            for entry in pending {
                do {
                    if restoring { try restore(deletionID: entry.id) }
                    else { try purge(deletionID: entry.id) }
                    completed.append(entry.id)
                } catch {
                    failed.append((entry, error))
                }
            }
            if !restoring || completed.count == before {
                skipped += failed.map { entry, error in
                    failure(.init(kind: entry.kind, id: entry.id), title: entry.title, error: error)
                }
                break
            }
            pending = failed.map { $0.0 }
        }
        return BatchRecoveryResult(completed: completed, skipped: skipped)
    }

    private func failure(_ target: LibraryDeletionTarget, title: String = "Item", error: any Error) -> BatchDeletionFailure {
        BatchDeletionFailure(target: target, title: title, error: error, reason: failureMessage(for: error, title: title))
    }
}
