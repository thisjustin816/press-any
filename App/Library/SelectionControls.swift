import EmulatorApplication
import SwiftUI

extension View {
    func selectionControls<ID: Hashable>(
        selection: Binding<ItemSelection<ID>>,
        available: Set<ID>,
        action: String = "Delete",
        selectAll: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        modifier(SelectionControls(selection: selection, available: available, action: action, selectAll: selectAll, perform: perform))
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
    let perform: () -> Void

    func body(content: Content) -> some View {
        content
            .environment(\.editMode, .constant(selection.isSelecting ? .active : .inactive))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selection.isSelecting ? "Done" : "Select") { selection.toggleMode() }
                        .disabled(available.isEmpty)
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
        let emptiedNames = Array(Set(items.flatMap { $0.plan.emptiedGames.map(\.primaryTitle) })).sorted()
        if items.contains(where: { $0.target.kind == .build }) && emptiedNames.isEmpty {
            parts.append("Games left without Builds go too, with their Save Profiles.")
        }
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
