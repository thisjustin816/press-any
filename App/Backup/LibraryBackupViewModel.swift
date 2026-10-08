import Combine
import Foundation
import Importing

struct LibraryBackupAppInfo: Sendable {
    let displayName: String
    let version: String
    let build: String

    @MainActor
    static var current: Self {
        Self(displayName: AppBrand.displayName,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
    }
}

@MainActor
final class LibraryBackupViewModel: ObservableObject {
    @Published var includeROMs = false
    @Published private(set) var summary: BackupSummary?
    @Published private(set) var isLoading = false
    @Published private(set) var isExporting = false
    @Published private(set) var progress = 0.0
    @Published private(set) var exportedURL: URL?
    @Published private(set) var errorMessage: String?

    let gameID: UUID?
    private let service: LibraryBackupService
    private let directory: URL
    private let appInfo: LibraryBackupAppInfo
    private var summaryRequestID = UUID()
    private var exportID = UUID()

    init(service: LibraryBackupService, directory: URL, gameID: UUID? = nil,
         appInfo: LibraryBackupAppInfo = .current) {
        self.service = service
        self.directory = directory
        self.gameID = gameID
        self.appInfo = appInfo
    }

    var canExport: Bool { summary.map { !$0.isTooLarge } ?? false && !isLoading && !isExporting }

    func loadSummary() async {
        guard !isExporting else { return }
        let requestID = UUID()
        summaryRequestID = requestID
        isLoading = true
        summary = nil
        errorMessage = nil
        let service = service, gameID = gameID, includeROMs = includeROMs
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try service.summary(gameID: gameID, includeROMs: includeROMs)
            }.value
            guard summaryRequestID == requestID else { return }
            summary = result
        } catch {
            guard summaryRequestID == requestID else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func export() async {
        guard canExport else { return }
        isExporting = true
        errorMessage = nil
        exportedURL = nil
        progress = 0
        let id = UUID()
        exportID = id
        defer { isExporting = false }
        let service = service, directory = directory, info = appInfo
        let includeROMs = includeROMs, gameID = gameID
        let onProgress: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor in
                guard let self, self.exportID == id, self.isExporting else { return }
                self.progress = max(self.progress, min(1, max(0, value)))
            }
        }
        do {
            exportedURL = try await Task.detached(priority: .userInitiated) {
                try service.export(to: directory, displayName: info.displayName,
                    appVersion: info.version, appBuild: info.build,
                    includeROMs: includeROMs, gameID: gameID, progress: onProgress)
            }.value
            progress = 1
        } catch { errorMessage = error.localizedDescription }
    }
}
