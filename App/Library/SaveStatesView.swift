import EmulatorApplication
import EmulatorDomain
import SwiftUI

/// A Save Profile's save states, newest first. Each can be renamed, or deleted into Recently
/// Deleted. Loading one stays in the game menu.
struct SaveStatesView: View {
    @StateObject private var model: SaveStatesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: SaveState?
    @State private var name = ""

    init(profile: SaveProfile, container: AppContainer) {
        _model = StateObject(wrappedValue: SaveStatesViewModel(
            profile: profile,
            repository: container.repositories.saveStates,
            builds: container.repositories.builds,
            assets: container.repositories.assets,
            fileStore: container.fileStore,
            deletion: container.libraryDeletion
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.states) { state in
                    row(state)
                }
            }
            .overlay {
                if model.states.isEmpty {
                    ContentUnavailableView(
                        "No Save States",
                        systemImage: "square.stack",
                        description: Text("Save State in the game menu adds one.")
                    )
                }
            }
            .navigationTitle("Save States")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Save State", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            ), presenting: renaming) { state in
                TextField("Name", text: $name)
                Button("Save") { model.rename(state, to: name) }
                Button("Cancel", role: .cancel) {}
            } message: { state in
                Text("Leave the name empty to call it \(state.kindName) again.")
            }
            .alert("Delete This Save State?", isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            ), presenting: model.pendingDeletion) { plan in
                Button("Delete", role: .destructive) { model.confirm(plan) }
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text("“\(plan.title)” waits in Recently Deleted for 30 days.")
            }
            .alert("Save States", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func row(_ state: SaveState) -> some View {
        HStack(spacing: 12) {
            thumbnail(state)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.displayName)
                Text(details(state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .leading) {
            Button("Rename") { startRenaming(state) }
                .tint(.blue)
        }
        .swipeActions(edge: .trailing) { SwipeDeleteButton { model.requestDeletion(of: state) } }
        .contextMenu {
            Button("Rename…") { startRenaming(state) }
            Button("Delete…", role: .destructive) { model.requestDeletion(of: state) }
        }
    }

    /// The Game Boy screen's shape, 160 by 144, with its pixels kept sharp.
    @ViewBuilder
    private func thumbnail(_ state: SaveState) -> some View {
        if let image = model.thumbnail(of: state) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: 80, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 80, height: 72)
                .accessibilityHidden(true)
        }
    }

    private func details(_ state: SaveState) -> String {
        let date = state.createdAt.formatted(date: .abbreviated, time: .shortened)
        guard let build = model.buildName(of: state) else { return date }
        return "\(build) · \(date)"
    }

    private func startRenaming(_ state: SaveState) {
        name = state.label ?? ""
        renaming = state
    }
}
