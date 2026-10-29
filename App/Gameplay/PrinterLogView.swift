import EmulationCore
import SwiftUI
import UIKit

/// The session's printer log: what the printer made of the game's traffic. Frames add to it off
/// the main thread; the Printer Log sheet reads it.
final class GameplayPrinterLog: @unchecked Sendable {
    static let capacity = 200
    private let lock = NSLock()
    private var entries: [PrinterEvent] = []

    var events: [PrinterEvent] { lock.withLock { entries } }

    func append(_ events: [PrinterEvent]) {
        lock.withLock {
            entries.append(contentsOf: events)
            if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        }
    }

    func clear() { lock.withLock { entries.removeAll() } }

    /// The log as plain text, oldest first, for sharing with a game's developer.
    static func text(_ events: [PrinterEvent]) -> String {
        events.map { event in
            let line = String(format: "%8.3f s  ", event.time) + event.summary
            return event.problem.map { "\(line)\n           \($0)" } ?? line
        }.joined(separator: "\n")
    }
}

/// Newest first, each line a packet and the status the game read back, with what went wrong
/// where the printer dropped or refused something.
struct PrinterLogView: View {
    let events: [PrinterEvent]
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(events.enumerated().reversed()), id: \.offset) { _, event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(event.summary).font(.callout.monospaced())
                                Spacer(minLength: 8)
                                Text(String(format: "%.2f s", event.time))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if let problem = event.problem {
                                Label(problem, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } footer: {
                    Text("Each packet the game sent, with the status it read back. Status checks show only when the answer changes. The newest \(GameplayPrinterLog.capacity) are kept until the game closes.")
                }
            }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView("Nothing Printed Yet", systemImage: "printer",
                                           description: Text("Packets appear here as the game talks to the printer."))
                }
            }
            .navigationTitle("Printer Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = GameplayPrinterLog.text(events)
                        copied = true
                    }
                    .disabled(events.isEmpty)
                }
            }
        }
    }
}
