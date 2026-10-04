import SwiftUI
import UIKit

/// A full SHA-256 on two lines of two 16-character groups. Left to wrap on its own, the hash
/// breaks wherever the line ends, with a hyphen that isn't part of it. Touch and hold copies it.
struct SHA256Row: View {
    let hash: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SHA-256")
            Text(Self.grouped(hash))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = hash
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    static func grouped(_ hash: String) -> String {
        let groups = stride(from: 0, to: hash.count, by: 16).map { start in
            String(hash.dropFirst(start).prefix(16))
        }
        return stride(from: 0, to: groups.count, by: 2)
            .map { groups[$0..<min($0 + 2, groups.count)].joined(separator: " ") }
            .joined(separator: "\n")
    }
}
