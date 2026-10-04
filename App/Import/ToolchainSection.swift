import EmulatorDomain
import SwiftUI

/// What toolchain detection found in an image: each engine, tool, and audio driver with its
/// version and how strongly it matched, or that nothing was recognized.
struct ToolchainSection: View {
    let reports: [ToolchainDetectionReport]

    @State private var showsAbout = false

    var body: some View {
        Section {
            let components = Self.displayOrder(reports.flatMap(\.components))
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
            HStack {
                Text("Made With")
                Spacer()
                Button {
                    showsAbout = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("About Made With")
                .popover(isPresented: $showsAbout) {
                    Text("A guess at how the game was made, from the code it contains. It never decides which Game a Build belongs to, and it can’t promise a save will carry over to another Build.")
                        .font(.callout)
                        .padding()
                        .frame(idealWidth: 300)
                        .fixedSize(horizontal: false, vertical: true)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    /// An engine such as GB Studio or ZGB is built on a toolchain such as GBDK, so it comes first,
    /// as what the game was really made with. Within a kind, detection's order is kept.
    static func displayOrder(_ components: [DetectedToolchainComponent]) -> [DetectedToolchainComponent] {
        let rank: [ToolchainComponentKind: Int] = [.engine: 0, .toolchain: 1, .musicDriver: 2, .soundEffectsDriver: 3]
        return components.enumerated()
            .sorted { (rank[$0.element.kind] ?? 4, $0.offset) < (rank[$1.element.kind] ?? 4, $1.offset) }
            .map(\.element)
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
