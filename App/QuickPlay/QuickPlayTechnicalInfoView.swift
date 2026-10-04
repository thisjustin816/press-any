import EmulatorDomain
import Foundation
import QuickPlay
import SwiftUI
import ToolchainDetection

/// A Quick Play ROM's identity and what it was made with. The session isn't in the library, so
/// detection runs on its copy of the ROM each time this opens.
struct QuickPlayTechnicalInfoView: View {
    let session: QuickPlaySession

    @State private var reports: [ToolchainDetectionReport]?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("ROM") {
                    LabeledContent("File", value: session.originalFilename)
                    LabeledContent("System", value: session.system.displayName)
                    SHA256Row(hash: session.imageSHA256)
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
            .task { await detect() }
        }
    }

    private func detect() async {
        let url = session.imageURL
        let system = session.system
        do {
            reports = try await Task.detached {
                ToolchainDetectorRegistry.standard.detect(image: try Data(contentsOf: url), system: system)
            }.value
        } catch {
            errorMessage = "Could not read the ROM: \(error.localizedDescription)"
        }
    }
}
