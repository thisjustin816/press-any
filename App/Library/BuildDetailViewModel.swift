import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation

@MainActor
final class BuildDetailViewModel: ObservableObject {
    @Published private(set) var build: Build?
    @Published var notesDraft = ""
    @Published var isEditingNotes = false
    @Published var errorMessage: String?

    private let buildID: UUID
    private let builds: any BuildRepository
    private let operations: BuildOperations

    init(buildID: UUID, builds: any BuildRepository, operations: BuildOperations) {
        self.buildID = buildID
        self.builds = builds
        self.operations = operations
    }

    func reload() {
        do {
            guard let fetched = try builds.fetchBuild(id: buildID) else {
                throw BuildOperationError.buildNotFound(buildID)
            }
            build = fetched
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func editNotes() {
        errorMessage = nil
        notesDraft = build?.notes ?? ""
        isEditingNotes = true
    }

    func saveNotes() {
        do {
            try operations.setNotes(buildID: buildID, notes: notesDraft)
            isEditingNotes = false
            reload()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
