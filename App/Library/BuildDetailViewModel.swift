import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation

@MainActor
final class BuildDetailViewModel: ObservableObject {
    struct SaveCompatibilityRow: Identifiable {
        let otherBuild: Build
        let compatibility: BuildSaveCompatibility
        var id: UUID { otherBuild.id }
        var label: String { compatibility.displayName }
    }

    @Published private(set) var build: Build?
    @Published private(set) var saveDeclarations: [SaveCompatibilityRow] = []
    @Published private(set) var compatibilityCandidates: [Build] = []
    @Published var isAddingCompatibility = false
    @Published var compatibilityBuildID: UUID?
    @Published var compatibilityDraft: BuildSaveCompatibility = .sharesSaves
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
            saveDeclarations = try builds.fetchSaveDeclarations(buildID: buildID).compactMap { declaration -> SaveCompatibilityRow? in
                guard let otherID = declaration.otherBuildID(than: buildID),
                      let other = try builds.fetchBuild(id: otherID) else { return nil }
                return SaveCompatibilityRow(otherBuild: other, compatibility: declaration.compatibility)
            }.sorted { $0.otherBuild.displayName.localizedCaseInsensitiveCompare($1.otherBuild.displayName) == .orderedAscending }
            compatibilityCandidates = try builds.fetchBuilds(gameID: fetched.gameID).filter { $0.id != buildID }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addCompatibility() {
        reload()
        guard errorMessage == nil else { return }
        compatibilityBuildID = compatibilityCandidates.first?.id
        compatibilityDraft = .sharesSaves
        isAddingCompatibility = true
    }

    func saveCompatibility() {
        guard let otherID = compatibilityBuildID else { return }
        do {
            try builds.setSaveCompatibility(between: buildID, and: otherID, compatibility: compatibilityDraft)
            isAddingCompatibility = false
            reload()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeCompatibility(otherBuildID: UUID) {
        do {
            try builds.removeSaveCompatibility(between: buildID, and: otherBuildID)
            reload()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
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
