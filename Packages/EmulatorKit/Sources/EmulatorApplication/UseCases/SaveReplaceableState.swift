import EmulatorDomain

struct SaveReplaceableState: Sendable {
    private let states: any SaveStateRepository
    private let transactions: any LibraryTransactionRunner

    init(states: any SaveStateRepository, transactions: any LibraryTransactionRunner) {
        self.states = states
        self.transactions = transactions
    }

    func execute(_ state: SaveState, kind: SaveStateKind, slot: Int? = nil) throws -> (saved: SaveState, previous: SaveState?) {
        try transactions.run {
            let previous = try states.fetchSaveStates(buildID: state.buildID, saveProfileID: state.saveProfileID)
                .first { existing in slot.map { existing.slot == $0 } ?? (existing.kind == .quick) }
            let saved = SaveState(
                id: previous?.id ?? state.id,
                buildID: state.buildID,
                saveProfileID: state.saveProfileID,
                core: state.core,
                stateSerializationVersion: state.stateSerializationVersion,
                stateAssetID: state.stateAssetID,
                screenshotAssetID: state.screenshotAssetID,
                kind: kind,
                slot: slot,
                isPinned: previous?.isPinned ?? state.isPinned,
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
