import EmulatorApplication
import SwiftUI

extension View {
    func selectionControls<ID: Hashable>(
        selection: Binding<ItemSelection<ID>>,
        available: Set<ID>,
        action: String = "Delete",
        selectAll: Bool = false,
        selectInToolbar: Bool = true,
        perform: @escaping () -> Void
    ) -> some View {
        modifier(SelectionControls(
            selection: selection, available: available, action: action, selectAll: selectAll,
            selectInToolbar: selectInToolbar, perform: perform
        ))
    }

    func batchDeletionAlert(
        plan: Binding<BatchDeletionPlan?>,
        noun: String,
        confirm: @escaping (BatchDeletionPlan) -> Void
    ) -> some View {
        let count = plan.wrappedValue?.count ?? 0
        return alert("Delete \(count) \(count == 1 ? String(noun.dropLast()) : noun)?", isPresented: Binding(
            get: { plan.wrappedValue != nil },
            set: { if !$0 { plan.wrappedValue = nil } }
        ), presenting: plan.wrappedValue) { batch in
            if !batch.items.isEmpty {
                Button("Delete (\(batch.items.count))", role: .destructive) { confirm(batch) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { batch in
            Text(batch.confirmationMessage)
        }
    }
}

private struct SelectionControls<ID: Hashable>: ViewModifier {
    @Binding var selection: ItemSelection<ID>
    let available: Set<ID>
    let action: String
    let selectAll: Bool
    /// False when a menu offers Select, as the library's does; Done still ends selecting here.
    let selectInToolbar: Bool
    let perform: () -> Void

    func body(content: Content) -> some View {
        content
            .environment(\.editMode, .constant(selection.isSelecting ? .active : .inactive))
            .toolbar {
                if selection.isSelecting || selectInToolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selection.isSelecting ? "Done" : "Select") { selection.toggleMode() }
                            .disabled(available.isEmpty)
                    }
                }
                if selection.isSelecting {
                    ToolbarItemGroup(placement: .bottomBar) {
                        if selectAll {
                            Button(selection.ids == available ? "Deselect All (\(available.count))" : "Select All (\(available.count))") {
                                selection.toggleAll(available)
                            }
                        }
                        Spacer()
                        Button("\(action) (\(selection.ids.count))", role: .destructive, action: perform)
                            .disabled(selection.ids.isEmpty)
                    }
                }
            }
            .onChange(of: available) { _, ids in selection.reconcile(with: ids) }
    }
}

extension BatchDeletionPlan {
    var confirmationMessage: String {
        var parts = [items.isEmpty ? "None of the selected items can be deleted." : "They wait in Recently Deleted for 30 days."]
        let dependentNames = Array(Set(items.flatMap { $0.plan.dependentBuilds.map(\.displayName) })).sorted()
        if !dependentNames.isEmpty {
            parts.append("Patched Builds go too: \(dependentNames.formatted(.list(type: .and))).")
        }
        let emptiedNames = emptiedGames.map(\.primaryTitle).sorted()
        if !emptiedNames.isEmpty {
            parts.append("Games left without Builds go too, with their Save Profiles: \(emptiedNames.formatted(.list(type: .and))).")
        }
        if !skipped.isEmpty {
            parts.append("\(skipped.count) will be skipped.")
            parts += skipped.map { "\($0.title): \($0.reason)" }
        }
        return parts.joined(separator: "\n\n")
    }
}

extension BatchDeletionResult {
    /// What failed while deleting, each item named. The confirmation already listed what planning
    /// skipped, so those aren't repeated.
    func failureMessage(after batch: BatchDeletionPlan) -> String? {
        let announced = Set(batch.skipped.map(\.target))
        let failures = skipped.filter { !announced.contains($0.target) }
        guard !failures.isEmpty else { return nil }
        return failures.map { "\($0.title): \($0.reason)" }.joined(separator: "\n\n")
    }
}
