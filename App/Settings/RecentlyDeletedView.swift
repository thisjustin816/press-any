import EmulatorApplication
import EmulatorDomain
import SwiftUI

/// Deleted Games, Builds, Save Profiles and save states, each restorable until 30 days after it
/// was deleted.
struct RecentlyDeletedView: View {
    let operations: LibraryDeletionOperations
    let games: any GameRepository

    @State private var deletions: [LibraryDeletion] = []
    @State private var purgeTarget: LibraryDeletion?
    @State private var selection = ItemSelection<UUID>()
    @State private var batchPurge: [UUID]?
    @State private var failure: (title: String, message: String)?

    // Split up so the compiler checks each part on its own; as one expression it timed out.
    var body: some View {
        content
            .alert(batchPurgeTitle, isPresented: Binding(
                get: { batchPurge != nil },
                set: { if !$0 { batchPurge = nil } }
            ), presenting: batchPurge) { ids in
                Button("Delete Now (\(ids.count))", role: .destructive) { purgeSelected(ids) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("They and everything that went with them are removed for good. This can’t be undone.")
            }
            .alert("Delete Now?", isPresented: Binding(
                get: { purgeTarget != nil },
                set: { if !$0 { purgeTarget = nil } }
            ), presenting: purgeTarget) { deletion in
                Button("Delete \(deletion.title)", role: .destructive) { purge(deletion) }
                Button("Cancel", role: .cancel) {}
            } message: { deletion in
                Text("\(deletion.title) and everything that went with it are removed for good. This can’t be undone.")
            }
            .alert(failure?.title ?? "", isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure?.message ?? "")
            }
    }

    private var content: some View {
        list
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(selection.isSelecting ? .active : .inactive))
            .toolbar { toolbar }
            .task { reload() }
    }

    private var list: some View {
        List(selection: selection.isSelecting ? $selection.ids : nil) {
            if !deletions.isEmpty {
                Section {
                    ForEach(deletions) { deletion in
                        row(deletion).tag(deletion.id)
                    }
                } footer: {
                    Text("Items are removed for good 30 days after deletion. Swipe for Restore and Delete Now.")
                }
            }
        }
        .overlay {
            if deletions.isEmpty {
                ContentUnavailableView(
                    "Nothing Recently Deleted",
                    systemImage: "trash",
                    description: Text("Deleted Games, Builds, Save Profiles and save states wait here for 30 days.")
                )
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(selection.isSelecting ? "Done" : "Select") { selection.toggleMode() }
                .disabled(deletions.isEmpty)
        }
        if selection.isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Restore (\(selection.ids.count))") { restoreSelected() }
                    .disabled(selection.ids.isEmpty)
                Spacer()
                Button("Delete Now (\(selection.ids.count))", role: .destructive) { batchPurge = selectedIDs }
                    .disabled(selection.ids.isEmpty)
            }
        }
    }

    private var batchPurgeTitle: String {
        let count = batchPurge?.count ?? 0
        return "Delete \(count) \(count == 1 ? "Item" : "Items") Now?"
    }

    private func row(_ deletion: LibraryDeletion) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(deletion.title)
            Text(subtitle(deletion))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .leading) {
            Button("Restore") { restore(deletion) }
                .tint(.blue)
        }
        .swipeActions(edge: .trailing) { SwipeDeleteButton(title: "Delete Now") { purgeTarget = deletion } }
        .contextMenu {
            if !selection.isSelecting {
                Button("Restore") { restore(deletion) }
                Button("Delete Now", role: .destructive) { purgeTarget = deletion }
            }
        }
    }

    private func subtitle(_ deletion: LibraryDeletion) -> String {
        var parts: [String] = []
        switch deletion.kind {
        case .game:
            parts.append("Game")
        case .build, .saveProfile, .saveState:
            let kind = switch deletion.kind {
            case .build: "Build"
            case .saveState: "Save State"
            default: "Save Profile"
            }
            if let game = try? games.fetchGame(id: deletion.gameID) {
                parts.append("\(kind) in \(game.primaryTitle)")
            } else {
                parts.append(kind)
            }
        }
        let days = max(1, Int((deletion.purgeDate.timeIntervalSinceNow / 86_400).rounded(.up)))
        parts.append(days == 1 ? "1 day left" : "\(days) days left")
        return parts.joined(separator: " · ")
    }

    private func reload() {
        deletions = (try? operations.recentlyDeleted()) ?? []
        selection.reconcile(with: Set(deletions.map(\.id)))
    }

    private func restore(_ deletion: LibraryDeletion) {
        let message: String
        do {
            try operations.restore(deletionID: deletion.id)
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            reload()
            return
        } catch {
            message = operations.failureMessage(for: error, title: deletion.title)
        }
        failure = ("Couldn’t Restore \(deletion.title)", message)
    }

    private func purge(_ deletion: LibraryDeletion) {
        do {
            try operations.purge(deletionID: deletion.id)
        } catch {
            failure = ("Couldn’t Delete \(deletion.title)", error.localizedDescription)
        }
        reload()
    }

    private var selectedIDs: [UUID] {
        deletions.filter { selection.ids.contains($0.id) }.map(\.id)
    }

    private func restoreSelected() {
        let result = operations.restore(deletionIDs: selectedIDs)
        finishBatch(result, title: "Couldn’t Restore \(result.skipped.count) \(result.skipped.count == 1 ? "Item" : "Items")")
    }

    private func purgeSelected(_ ids: [UUID]) {
        let result = operations.purge(deletionIDs: ids)
        finishBatch(result, title: "Couldn’t Delete \(result.skipped.count) \(result.skipped.count == 1 ? "Item" : "Items")")
    }

    private func finishBatch(_ result: BatchRecoveryResult, title: String) {
        reload()
        selection.ids.subtract(result.completed)
        if !result.completed.isEmpty {
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }
        if !result.skipped.isEmpty {
            failure = (title, result.skipped.map { "\($0.title): \($0.reason)" }.joined(separator: "\n\n"))
        }
    }
}
