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
                    let shown = ToolchainDisplay(component)
                    LabeledContent {
                        if let version = shown.version {
                            Text(version)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shown.name)
                            Text(Self.detail(component, variant: shown.variant))
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

    private static func detail(_ component: DetectedToolchainComponent, variant: String?) -> String {
        let kind = variant.map { "\(kindName(component.kind)) (\($0))" } ?? kindName(component.kind)
        return "\(kind), \(confidenceName(component.confidence))"
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

/// A detected component as the interface shows it. The detector's labels are kept as written in
/// the stored report; this turns them into the names and versions people know.
struct ToolchainDisplay: Equatable {
    let name: String
    /// One version or a range, such as "4.3.0 or later" or "2.0.18 to 2.1.5". Nil when unknown.
    let version: String?
    /// A named edition of an audio driver, such as hUGETracker's SuperDisk.
    let variant: String?

    private static let names = ["GBStudio": "GB Studio", "GBBasic": "GB BASIC"]

    init(_ component: DetectedToolchainComponent) {
        var name = Self.names[component.name] ?? component.name
        var label = component.version.flatMap { $0.isEmpty || $0 == "Unknown" ? nil : $0 }
        // Audio drivers name editions where other components put versions. Editions are words, such
        // as SuperDisk or X2; a label of digits and dots is a version.
        let isVersionNumber = label.map { !$0.isEmpty && $0.allSatisfy { $0.isNumber || $0 == "." } } ?? false
        if let edition = label, component.kind == .musicDriver || component.kind == .soundEffectsDriver,
           !edition.contains("."), !isVersionNumber {
            variant = edition
            label = nil
        } else {
            variant = nil
        }
        // The detector numbers GBDK-2020 releases 2020.x.y.z; the project calls them GBDK-2020 x.y.z.
        // A range reaching back into the original GBDK keeps the detector's numbering, since the
        // two projects' version numbers overlap.
        if let range = label, name == "GBDK" {
            let parts = range.components(separatedBy: " - ")
            if parts.allSatisfy({ $0.hasPrefix("2020.") }) {
                name = "GBDK-2020"
                label = parts.map { String($0.dropFirst(5)) }.joined(separator: " - ")
            }
        }
        self.name = name
        version = label.map {
            let range = $0.replacingOccurrences(of: " - ", with: " to ")
            return range.hasSuffix("+") ? String(range.dropLast()) + " or later" : range
        }
    }

    init(name: String, version: String?, variant: String?) {
        self.name = name
        self.version = version
        self.variant = variant
    }
}
