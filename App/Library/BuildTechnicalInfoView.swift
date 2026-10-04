import EmulatorDomain
import SwiftUI

/// A Build's exact identity and what it was made with. Opening it detects the image again, so a
/// Build imported before detection, or under older signatures, shows current findings.
struct BuildTechnicalInfoView: View {
    let build: Build
    let container: AppContainer

    @State private var reports: [ToolchainDetectionReport]?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Build") {
                    LabeledContent("Name", value: build.displayName)
                    LabeledContent("System", value: build.system == .gameBoyColor ? "Game Boy Color" : "Game Boy")
                    LabeledContent("Source", value: build.sourceKind == .patchRecipe ? "Patched" : "Imported")
                    if let pin = build.corePin {
                        LabeledContent("Core", value: "\(pin.descriptor.identifier) \(pin.descriptor.version)")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SHA-256")
                        Text(build.imageSHA256)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let reports {
                    ToolchainSection(reports: reports)
                } else if let errorMessage {
                    Section("Made With") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                } else {
                    Section("Made With") {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Technical Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        let refresh = container.toolchainRefresh
        let build = build
        do {
            reports = try await Task.detached { try refresh.execute(build: build) }.value
        } catch {
            errorMessage = "Could not read the Build’s image: \(error.localizedDescription)"
        }
    }
}
