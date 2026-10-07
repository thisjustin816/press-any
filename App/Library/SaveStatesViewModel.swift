import AssetStorage
import EmulatorApplication
import EmulatorDomain
import Foundation
import UIKit

/// One Save Profile's save states, on every Build, for naming and deleting.
@MainActor
final class SaveStatesViewModel: ObservableObject {
    @Published private(set) var states: [SaveState] = []
    @Published var pendingDeletion: DeletionPlan?
    @Published var errorMessage: String?

    let profile: SaveProfile
    private let repository: any SaveStateRepository
    private let builds: any BuildRepository
    private let assets: any ManagedAssetRepository
    private let fileStore: ManagedFileStore
    private let deletion: LibraryDeletionOperations
    private var buildNames: [UUID: String] = [:]
    private var thumbnails: [UUID: UIImage] = [:]

    init(
        profile: SaveProfile,
        repository: any SaveStateRepository,
        builds: any BuildRepository,
        assets: any ManagedAssetRepository,
        fileStore: ManagedFileStore,
        deletion: LibraryDeletionOperations
    ) {
        self.profile = profile
        self.repository = repository
        self.builds = builds
        self.assets = assets
        self.fileStore = fileStore
        self.deletion = deletion
        reload()
    }

    func reload() {
        do {
            states = try repository.fetchSaveStates(saveProfileID: profile.id)
            buildNames = Dictionary(
                try builds.fetchBuilds(gameID: profile.gameID).map { ($0.id, $0.displayName) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func buildName(of state: SaveState) -> String? {
        buildNames[state.buildID]
    }

    /// The picture taken when the state was saved, or nil when it has none or its file is missing.
    func thumbnail(of state: SaveState) -> UIImage? {
        if let cached = thumbnails[state.id] { return cached }
        guard let assetID = state.screenshotAssetID,
              let asset = try? assets.fetchAsset(id: assetID),
              let url = try? fileStore.managedURL(relativePath: asset.relativePath),
              let data = try? fileStore.readData(at: url),
              let image = UIImage(data: data) else { return nil }
        thumbnails[state.id] = image
        return image
    }

    /// An empty name clears it, and the state shows its kind again.
    func rename(_ state: SaveState, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try repository.renameSaveState(id: state.id, label: trimmed.isEmpty ? nil : trimmed)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestDeletion(of state: SaveState) {
        do {
            pendingDeletion = try deletion.planStateDeletion(stateID: state.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirm(_ plan: DeletionPlan) {
        do {
            try deletion.delete(plan)
            reload()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
