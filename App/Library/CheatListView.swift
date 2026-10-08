import EmulatorApplication
import EmulatorDomain
import SwiftUI

/// A Build's cheats, each with its own switch, above the Build's Cheats On switch. Opened from the
/// game menu over the paused game, or from the Build's menu.
struct CheatListView: View {
    @StateObject private var model: CheatListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isReordering = false

    /// `onChange` runs after each saved change, so a running game applies it.
    init(buildID: UUID, container: AppContainer, onChange: @escaping () throws -> Void = {}) {
        _model = StateObject(wrappedValue: CheatListViewModel(
            buildID: buildID,
            builds: container.repositories.builds,
            operations: container.buildCheats,
            isValid: container.cheatCodeChecker(buildID: buildID),
            onChange: onChange
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.cheats) { cheat in
                        row(cheat)
                    }
                    .onMove(perform: moveAction)
                    if !isReordering {
                        Button("Add Cheat…", systemImage: "plus") { model.startAdding() }
                            .accessibilityIdentifier("cheats.add")
                    }
                }
                Section {
                    Toggle("Cheats On", isOn: Binding(
                        get: { model.cheatsEnabled },
                        set: { model.setCheatsEnabled($0) }
                    ))
                    .accessibilityIdentifier("cheats.master")
                } footer: {
                    Text("Cheats can change a game’s save. A backup, or a second Save Profile for playing with cheats, keeps the save safe.")
                }
            }
            .environment(\.editMode, .constant(isReordering ? .active : .inactive))
            .navigationTitle("Cheats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.cheats.count > 1 {
                        Button(isReordering ? "Done" : "Reorder") { isReordering.toggle() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isReordering { Button("Done") { dismiss() } }
                }
            }
            .task { model.reload() }
            .sheet(isPresented: $model.isEditing) { editor }
            .alert("Delete This Cheat?", isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            ), presenting: model.pendingDeletion) { cheat in
                Button("Delete", role: .destructive) { model.confirmDeletion(of: cheat) }
                Button("Cancel", role: .cancel) {}
            } message: { cheat in
                Text("“\(cheat.name)” is deleted for good.")
            }
            .alert("Cheats", isPresented: Binding(
                get: { model.errorMessage != nil && !model.isEditing },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    /// Nil outside Reorder, so a drag can't move a row by accident.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard isReordering else { return nil }
        return { source, destination in
            var ids = model.cheats.map(\.id)
            ids.move(fromOffsets: source, toOffset: destination)
            model.reorder(ids)
        }
    }

    private func row(_ cheat: BuildCheat) -> some View {
        Toggle(isOn: Binding(
            get: { cheat.isEnabled },
            set: { model.setEnabled(cheat, $0) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(cheat.name)
                Text(cheat.codes.joined(separator: " "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("cheats.row.\(cheat.id.uuidString)")
        .swipeActions(edge: .trailing) {
            SwipeDeleteButton { model.requestDeletion(of: cheat) }
            Button("Edit") { model.startEditing(cheat) }
                .tint(.blue)
        }
        .contextMenu {
            Button("Edit Cheat…", systemImage: "pencil") { model.startEditing(cheat) }
            Button(role: .destructive) { model.requestDeletion(of: cheat) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var editor: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $model.nameDraft)
                    .accessibilityIdentifier("cheats.name")
                Section {
                    TextEditor(text: $model.codesDraft)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(minHeight: 120)
                        .accessibilityLabel("Codes")
                        .accessibilityIdentifier("cheats.codes")
                    if let error = model.draftError {
                        Text(error).foregroundStyle(.red)
                    }
                } header: {
                    Text("Codes")
                } footer: {
                    Text("One code per line: Game Genie (ABC-DEF or ABC-DEF-GHI) or GameShark (01VVAAAA). They apply together.")
                }
            }
            .navigationTitle(model.editingCheatID == nil ? "Add Cheat" : "Edit Cheat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.isEditing = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.saveDraft() }
                        .disabled(model.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.codesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
