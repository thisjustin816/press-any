import SwiftUI
import UIKit

/// A full SHA-256 on two lines of two 16-character groups, or one group a line at accessibility
/// text sizes. Left to wrap on its own, the hash breaks wherever the line ends, with a hyphen that
/// isn't part of it, so each line shrinks to fit instead. Touch and hold copies it.
struct SHA256Row: View {
    let hash: String
    var title = "SHA-256"

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            ForEach(Array(Self.lines(hash, groupsPerLine: typeSize.isAccessibilitySize ? 1 : 2).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button {
                UIPasteboard.general.string = hash
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    static func lines(_ hash: String, groupsPerLine: Int) -> [String] {
        let groups = stride(from: 0, to: hash.count, by: 16).map { start in
            String(hash.dropFirst(start).prefix(16))
        }
        return stride(from: 0, to: groups.count, by: groupsPerLine)
            .map { groups[$0..<min($0 + groupsPerLine, groups.count)].joined(separator: " ") }
    }
}
