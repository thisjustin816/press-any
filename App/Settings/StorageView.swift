import EmulatorApplication
import Foundation
import QuickPlay
import SwiftUI

struct StorageView: View {
    let container: AppContainer
    let onResumeQuickPlay: (QuickPlaySession) -> Void

    @State private var usage: LibraryStorageUsage?
    @State private var freeBytes: Int64?
    @State private var errorMessage: String?
    @State private var showsClearConfirmation = false
    @State private var showsQuickPlaySessions = false
    @State private var quickPlayToResume: QuickPlaySession?

    var body: some View {
        Form {
            Section {
                if let usage {
                    LabeledContent("Library Total", value: formatted(usage.totalBytes))
                    LabeledContent("Device Free Space", value: freeBytes.map(formatted) ?? "Unavailable")
                } else if errorMessage == nil {
                    ProgressView("Measuring storage...")
                }
            }

            if let usage {
                Section {
                    ForEach([LibraryStorageCategory.gameROMs, .patches, .saves, .saveStates, .artwork, .other], id: \.self) { category in
                        LabeledContent(category.title, value: size(usage.bytes(in: category)))
                    }
                } header: {
                    Text("Your Data")
                } footer: {
                    Text("Original files and progress that can't be rebuilt. Save States includes their thumbnails.")
                }

                Section {
                    LabeledContent("Patched ROM Cache", value: size(usage.bytes(in: .patchedROMCache)))
                    Button { showsQuickPlaySessions = true } label: {
                        HStack {
                            LabeledContent("Quick Play", value: size(usage.bytes(in: .quickPlay)))
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                    Button("Clear Patched ROM Cache", role: .destructive) { showsClearConfirmation = true }
                        .disabled(usage.bytes(in: .patchedROMCache) == 0)
                } header: {
                    Text("Rebuildable and Temporary")
                } footer: {
                    Text("Patched Builds rebuild their ROMs when needed. Quick Play includes kept sessions, which expire.")
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .alert("Clear Patched ROM Cache?", isPresented: $showsClearConfirmation) {
            Button("Clear Cache", role: .destructive) {
                Task { await clearCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Patched Builds rebuild their ROM the next time they're played. Original ROMs, patches and saves are kept. A running Build's ROM is kept too.")
        }
        .sheet(isPresented: $showsQuickPlaySessions, onDismiss: {
            Task { await refresh() }
            if let session = quickPlayToResume {
                quickPlayToResume = nil
                onResumeQuickPlay(session)
            }
        }) {
            QuickPlaySessionsView(container: container) { quickPlayToResume = $0 }
        }
    }

    private func clearCache() async {
        errorMessage = nil
        var clearError: String?
        do { try container.clearPatchedROMCache() }
        catch { clearError = "Could not clear the cache: \(error.localizedDescription)" }
        await refresh()
        if let clearError { errorMessage = clearError }
    }

    private func refresh() async {
        let measure = container.storageUsage
        let root = container.fileStore.rootURL
        do {
            let result = try await Task.detached(priority: .utility) {
                let usage = try measure.execute()
                let free = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    .volumeAvailableCapacityForImportantUsage
                return (usage, free)
            }.value
            usage = result.0
            freeBytes = result.1
            errorMessage = nil
        } catch {
            usage = nil
            errorMessage = "Could not measure storage: \(error.localizedDescription)"
        }
    }

    private func size(_ bytes: Int64) -> String { bytes == 0 ? "None" : formatted(bytes) }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private extension LibraryStorageCategory {
    var title: String {
        switch self {
        case .gameROMs: "Game ROMs"
        case .patches: "Patches"
        case .saves: "Saves"
        case .saveStates: "Save States"
        case .artwork: "Artwork"
        case .other: "Other"
        case .patchedROMCache: "Patched ROM Cache"
        case .quickPlay: "Quick Play"
        }
    }
}
