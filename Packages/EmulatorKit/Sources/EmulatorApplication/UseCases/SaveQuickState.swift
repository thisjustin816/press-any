import EmulatorDomain

public struct SaveQuickState: Sendable {
    private let states: any SaveStateRepository
    private let transactions: any LibraryTransactionRunner

    public init(states: any SaveStateRepository, transactions: any LibraryTransactionRunner) {
        self.states = states
        self.transactions = transactions
    }

    public func execute(_ state: SaveState) throws -> (saved: SaveState, previous: SaveState?) {
        try transactions.run {
            let previous = try states.fetchSaveStates(buildID: state.buildID, saveProfileID: state.saveProfileID)
                .first { $0.kind == .quick }
            let saved = SaveState(
                id: previous?.id ?? state.id,
                buildID: state.buildID,
                saveProfileID: state.saveProfileID,
                core: state.core,
                stateSerializationVersion: state.stateSerializationVersion,
                stateAssetID: state.stateAssetID,
                screenshotAssetID: state.screenshotAssetID,
                kind: .quick,
                label: previous?.label,
                playtimeSeconds: state.playtimeSeconds,
                createdAt: state.createdAt
            )
            if previous != nil {
                try states.updateSaveState(saved)
            } else {
                try states.insertSaveState(saved)
            }
            return (saved, previous)
        }
    }
}
