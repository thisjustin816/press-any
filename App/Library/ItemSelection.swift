import Foundation

struct ItemSelection<ID: Hashable> {
    var isSelecting = false
    var ids = Set<ID>()

    mutating func toggleMode() {
        isSelecting.toggle()
        ids.removeAll()
    }

    mutating func toggle(_ id: ID) {
        guard isSelecting else { return }
        if !ids.insert(id).inserted { ids.remove(id) }
    }

    mutating func reconcile(with available: Set<ID>) {
        ids.formIntersection(available)
        if available.isEmpty {
            isSelecting = false
            ids.removeAll()
        }
    }

    mutating func toggleAll(_ available: Set<ID>) {
        guard isSelecting else { return }
        ids = ids == available ? [] : available
    }
}
