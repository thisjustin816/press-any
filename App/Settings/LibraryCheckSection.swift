import AssetStorage
import SwiftUI

/// Checks the library's files against the database: missing files, damaged ROMs and patches,
/// and leftover source or generated files that nothing uses, which it removes.
struct LibraryCheckSection: View {
    let checker: ManagedAssetIntegrityChecker

    @State private var checking = false
    @State private var result: String?

    var body: some View {
        Section {
            Button {
                Task { await check() }
            } label: {
                HStack {
                    Text("Check Library Files")
                    if checking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(checking)
            if let result {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Rereads every ROM and patch, so a large library takes a moment.")
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        let checker = checker
        do {
            let report = try await Task.detached { try checker.inspect(cleanup: .removeProvableOrphans) }.value
            result = Self.summary(of: report)
        } catch {
            result = "Couldn’t check the library: \(error.localizedDescription)"
        }
    }

    static func summary(of report: ManagedAssetIntegrityReport) -> String {
        var missingSources = 0, missingUserData = 0, missingGenerated = 0, damaged = 0
        for issue in report.issues {
            switch issue {
            case .missingSource: missingSources += 1
            case .missingUserData: missingUserData += 1
            case .missingCache: missingGenerated += 1
            case .hashMismatch: damaged += 1
            case .orphanSource, .orphanCache: break
            }
        }
        var lines: [String] = []
        if damaged > 0 {
            lines.append("\(count(damaged, "ROM or patch file is", "ROM or patch files are")) damaged. Importing the same file again repairs it.")
        }
        if missingSources > 0 {
            lines.append("\(count(missingSources, "ROM or patch file is", "ROM or patch files are")) missing. Importing the same file again restores it.")
        }
        if missingUserData > 0 {
            lines.append("\(count(missingUserData, "save, state, or artwork file is", "save, state, or artwork files are")) missing.")
        }
        if missingGenerated > 0 {
            lines.append("\(count(missingGenerated, "patched Build’s image", "patched Builds’ images")) will be rebuilt when played.")
        }
        if !report.removedRelativePaths.isEmpty {
            lines.append("Removed \(count(report.removedRelativePaths.count, "leftover file", "leftover files")) that nothing used.")
        }
        return lines.isEmpty ? "Every library file is present and intact." : lines.joined(separator: "\n")
    }

    private static func count(_ number: Int, _ singular: String, _ plural: String) -> String {
        "\(number) \(number == 1 ? singular : plural)"
    }
}
