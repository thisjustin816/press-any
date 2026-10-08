import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation

/// One Build's cheats, from the game menu or the Build's menu. Each change is saved at once and
/// then handed to `onChange`, which applies it to a running game.
@MainActor
final class CheatListViewModel: ObservableObject {
    @Published private(set) var cheats: [BuildCheat] = []
    @Published private(set) var cheatsEnabled = true
    /// The add or edit sheet is open. `editingCheatID` is nil while adding.
    @Published var isEditing = false
    @Published private(set) var editingCheatID: UUID?
    @Published var nameDraft = ""
    @Published var codesDraft = ""
    /// Why the draft wasn't saved, such as the line that isn't a code.
    @Published private(set) var draftError: String?
    @Published var pendingDeletion: BuildCheat?
    @Published var errorMessage: String?

    let buildID: UUID
    private let builds: any BuildRepository
    private let operations: BuildCheatOperations
    private let isValid: (String) -> Bool
    private let onChange: () throws -> Void

    /// `isValid` is the core's check for one code.
    init(buildID: UUID, builds: any BuildRepository, operations: BuildCheatOperations,
         isValid: @escaping (String) -> Bool, onChange: @escaping () throws -> Void = {}) {
        self.buildID = buildID
        self.builds = builds
        self.operations = operations
        self.isValid = isValid
        self.onChange = onChange
    }

    func reload() {
        do {
            guard let build = try builds.fetchBuild(id: buildID) else { throw BuildOperationError.buildNotFound(buildID) }
            cheatsEnabled = build.cheatsEnabled
            cheats = try operations.cheats(buildID: buildID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAdding() {
        editingCheatID = nil
        nameDraft = ""
        codesDraft = ""
        draftError = nil
        isEditing = true
    }

    func startEditing(_ cheat: BuildCheat) {
        editingCheatID = cheat.id
        nameDraft = cheat.name
        codesDraft = CheatCodeText.text(of: cheat.codes)
        draftError = nil
        isEditing = true
    }

    /// Saves nothing unless the name is there and every line reads; the sheet stays open with the
    /// reason otherwise.
    func saveDraft() {
        do {
            if let editingCheatID {
                try operations.edit(cheatID: editingCheatID, name: nameDraft, codes: codesDraft, isValid: isValid)
            } else {
                try operations.add(buildID: buildID, name: nameDraft, codes: codesDraft, isValid: isValid)
            }
        } catch {
            draftError = error.localizedDescription
            return
        }
        draftError = nil
        isEditing = false
        changed()
    }

    func setEnabled(_ cheat: BuildCheat, _ isEnabled: Bool) {
        perform { try operations.setEnabled(cheatID: cheat.id, isEnabled) }
    }

    func setCheatsEnabled(_ enabled: Bool) {
        perform { try operations.setCheatsEnabled(buildID: buildID, enabled: enabled) }
    }

    /// Puts the cheats in this order, as a drag leaves them.
    func reorder(_ ids: [UUID]) {
        perform { try operations.reorder(buildID: buildID, orderedIDs: ids) }
    }

    func requestDeletion(of cheat: BuildCheat) {
        pendingDeletion = cheat
    }

    func confirmDeletion(of cheat: BuildCheat) {
        pendingDeletion = nil
        perform { try operations.delete(cheatID: cheat.id) }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            errorMessage = error.localizedDescription
            reload()
            return
        }
        changed()
    }

    private func changed() {
        reload()
        do {
            try onChange()
        } catch {
            errorMessage = "The change was saved, but the game couldn’t apply it: \(error.localizedDescription)"
        }
    }
}
