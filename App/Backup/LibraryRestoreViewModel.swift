import Combine
import EmulatorApplication
import Foundation
import Importing

@MainActor
final class LibraryRestoreViewModel: ObservableObject {
    @Published private(set) var prepared: PreparedLibraryRestore?
    @Published private(set) var review: LibraryRestoreReview?
    @Published private(set) var choices: [String: RestoreChoice] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isMakingSafetyBackup = false
    @Published private(set) var isRestoring = false
    @Published private(set) var progress = 0.0
    @Published private(set) var report: RestoreReport?
    @Published private(set) var safetyBackupURL: URL?
    @Published var isReplacementConfirmationPresented = false
    @Published private(set) var errorMessage: String?

    let url: URL
    private let service: LibraryBackupService
    private let directory: URL
    private let appInfo: LibraryBackupAppInfo
    private let isSessionActive: @MainActor () -> Bool
    private var restoreID = UUID()

    init(service: LibraryBackupService, url: URL, directory: URL,
         appInfo: LibraryBackupAppInfo = .current,
         isSessionActive: @escaping @MainActor () -> Bool) {
        self.service = service
        self.url = url
        self.directory = directory
        self.appInfo = appInfo
        self.isSessionActive = isSessionActive
    }

    var isBusy: Bool { isLoading || isMakingSafetyBackup || isRestoring }
    var sessionIsActive: Bool { isSessionActive() }
    var canRestore: Bool {
        guard prepared != nil, let review, !isBusy, report == nil else { return false }
        return review.conflicts.allSatisfy { choices[$0.id] != nil }
    }
    var canReplaceLibrary: Bool {
        prepared?.manifest.isGamePackage == false && review != nil && !isBusy && report == nil
    }

    func load() async {
        guard !isBusy, report == nil else { return }
        isLoading = true
        errorMessage = nil
        prepared = nil
        review = nil
        choices = [:]
        safetyBackupURL = nil
        isReplacementConfirmationPresented = false
        defer { isLoading = false }
        let service = service, url = url
        do {
            let (prepared, review) = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let prepared = try service.prepare(from: url)
                return (prepared, try service.review(prepared))
            }.value
            self.prepared = prepared
            self.review = review
            choices = Dictionary(uniqueKeysWithValues: review.conflicts
                .filter { !$0.requiresExplicitChoice }
                .map { ($0.id, $0.suggestedChoice) })
        } catch { errorMessage = error.localizedDescription }
    }

    func choose(_ choice: RestoreChoice?, for conflictID: String) {
        guard !isBusy, let conflict = review?.conflicts.first(where: { $0.id == conflictID }),
              choice != .keepBoth || conflict.allowsKeepBoth else { return }
        choices[conflictID] = choice
    }

    func merge() async {
        guard canRestore, allowRestore() else { return }
        await restore(replacingLibrary: false)
    }

    func prepareReplacement() async {
        guard canReplaceLibrary, allowRestore(), let prepared, let review else { return }
        isMakingSafetyBackup = true
        errorMessage = nil
        safetyBackupURL = nil
        isReplacementConfirmationPresented = false
        defer { isMakingSafetyBackup = false }
        let service = service, directory = directory, info = appInfo
        do {
            safetyBackupURL = try await Task.detached(priority: .userInitiated) {
                try service.makeSafetyBackup(for: prepared, review: review, to: directory,
                    displayName: info.displayName, appVersion: info.version, appBuild: info.build)
            }.value
            if allowRestore() { isReplacementConfirmationPresented = true }
        } catch { errorMessage = error.localizedDescription }
    }

    func cancelReplacement() {
        isReplacementConfirmationPresented = false
    }

    func confirmReplacement() async {
        guard isReplacementConfirmationPresented, safetyBackupURL != nil,
              canReplaceLibrary, allowRestore() else { return }
        isReplacementConfirmationPresented = false
        await restore(replacingLibrary: true)
    }

    private func allowRestore() -> Bool {
        guard !isSessionActive() else {
            errorMessage = "Close the current game before restoring."
            return false
        }
        return true
    }

    private func restore(replacingLibrary: Bool) async {
        guard let prepared, let review else { return }
        isRestoring = true
        errorMessage = nil
        progress = 0
        let id = UUID()
        restoreID = id
        defer { isRestoring = false }
        let service = service, choices = choices
        let safetyURL = replacingLibrary ? safetyBackupURL : nil
        let onProgress: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor in
                guard let self, self.restoreID == id, self.isRestoring else { return }
                self.progress = max(self.progress, min(1, max(0, value)))
            }
        }
        do {
            report = try await Task.detached(priority: .userInitiated) {
                try service.restore(prepared, review: review, choices: choices,
                    replaceEntireLibrary: replacingLibrary, safetyBackupURL: safetyURL, progress: onProgress)
            }.value
            progress = 1
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch { errorMessage = error.localizedDescription }
    }
}
