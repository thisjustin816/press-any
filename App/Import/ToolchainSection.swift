import EmulatorDomain
import SwiftUI

/// What toolchain detection found in an image: each tool, engine and audio driver with its
/// version and how strongly it matched, or that nothing was recognized.
struct ToolchainSection: View {
    let reports: [ToolchainDetectionReport]

    var body: some View {
        Section {
            let components = reports.flatMap(\.components)
            if components.isEmpty {
                Text("Not recognized")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                    LabeledContent {
                        Text(component.version ?? "Version unknown")
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(component.name)
                            Text("\(Self.kindName(component.kind)), \(Self.confidenceName(component.confidence))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Made With")
        } footer: {
            Text("A guess at how the game was made, from \(sources). It never decides which Game a Build belongs to or whether its saves carry over.")
        }
    }

    private var sources: String {
        let names = reports.map { "\($0.detector) \($0.corpusRevision)" }
        return names.isEmpty ? "no detector" : names.joined(separator: " and ")
    }

    private static func kindName(_ kind: ToolchainComponentKind) -> String {
        switch kind {
        case .toolchain: "Toolchain"
        case .engine: "Engine"
        case .musicDriver: "Music driver"
        case .soundEffectsDriver: "Sound effects driver"
        }
    }

    private static func confidenceName(_ confidence: ToolchainConfidence) -> String {
        switch confidence {
        case .high: "several signatures matched"
        case .medium: "one signature matched"
        case .low: "inferred"
        }
    }
}
