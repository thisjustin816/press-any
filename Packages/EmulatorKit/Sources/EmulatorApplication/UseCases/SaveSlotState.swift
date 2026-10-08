import EmulatorDomain

public struct SaveSlotState: Sendable {
    private let replacement: SaveReplaceableState

    public init(states: any SaveStateRepository, transactions: any LibraryTransactionRunner) {
        replacement = SaveReplaceableState(states: states, transactions: transactions)
    }

    public func execute(_ state: SaveState) throws -> (saved: SaveState, previous: SaveState?) {
        guard state.kind == .slot, let slot = state.slot, slot > 0 else {
            throw SaveSlotStateError.invalidSlot
        }
        return try replacement.execute(state, kind: .slot, slot: slot)
    }
}

public enum SaveSlotStateError: Error, Equatable {
    case invalidSlot
}
