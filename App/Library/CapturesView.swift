import EmulationCore
import EmulatorApplication
import EmulatorDomain
import SwiftUI
import UIKit

/// A print's paper as a small grayscale picture, margins included, for lists and grids.
enum PrintThumbnail {
    static func image(for slip: PrinterSlip) -> UIImage? {
        let width = PrinterOutput.width
        var pixels = Data()
        for section in slip.sections {
            pixels.append(Data(repeating: 0xFF, count: width * section.topMargin * 8))
            pixels.append(section.luminance)
            pixels.append(Data(repeating: 0xFF, count: width * section.bottomMargin * 8))
        }
        let height = pixels.count / width
        guard height > 0, let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// A print with its paper and thumbnail, read off the main thread. The thumbnail never changes
/// after.
struct CapturedPrint: Identifiable, @unchecked Sendable {
    let capture: Capture
    let slip: PrinterSlip
    let thumbnail: UIImage?
    var id: UUID { capture.id }

    /// Nil when the print's file can't be read, which leaves it out rather than failing the rest.
    static func read(_ capture: Capture, from prints: PrintCaptures) -> CapturedPrint? {
        guard let slip = try? prints.slip(for: capture) else { return nil }
        return CapturedPrint(capture: capture, slip: slip, thumbnail: PrintThumbnail.image(for: slip))
    }
}

/// A Game's prints, read once and shown newest first.
@MainActor
final class CapturesModel: ObservableObject {
    typealias Item = CapturedPrint

    @Published private(set) var items: [Item] = []
    @Published private(set) var builds: [Build] = []
    @Published var errorMessage: String?
    let gameID: UUID
    private let container: AppContainer

    init(container: AppContainer, gameID: UUID) {
        self.container = container
        self.gameID = gameID
    }

    func load() async {
        let prints = container.printCaptures
        let gameID = gameID
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try prints.captures(gameID: gameID).compactMap { CapturedPrint.read($0, from: prints) }
            }.value
            items = loaded
            builds = (try? container.repositories.builds.fetchBuilds(gameID: gameID)) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPinned(_ pinned: Bool, _ item: Item) async {
        do {
            try container.printCaptures.setPinned(pinned, captureID: item.id)
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
        await load()
    }

    func delete(_ item: Item) async {
        do {
            let deletion = container.libraryDeletion
            try deletion.delete(deletion.planCaptureDeletion(captureIDs: [item.id]))
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            errorMessage = container.libraryDeletion.failureMessage(for: error, title: "Print")
        }
        await load()
    }

    func artworkURL() -> URL? {
        guard let game = try? container.repositories.games.fetchGame(id: gameID) else { return nil }
        return container.artworkURL(for: game)
    }
}

/// The Game's Captures: its prints in a grid, filterable by the Build they came from.
struct CapturesView: View {
    @StateObject private var model: CapturesModel
    @Environment(\.dismiss) private var dismiss
    /// Nil shows every Build.
    @State private var buildFilter: UUID?
    @State private var opened: CapturedPrint?

    init(container: AppContainer, gameID: UUID) {
        _model = StateObject(wrappedValue: CapturesModel(container: container, gameID: gameID))
    }

    private var shown: [CapturedPrint] {
        guard let buildFilter else { return model.items }
        return model.items.filter { $0.capture.buildID == buildFilter }
    }

    /// Builds that made at least one print, in the Game's order.
    private var printingBuilds: [Build] {
        let used = Set(model.items.compactMap(\.capture.buildID))
        return model.builds.filter { used.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.items.isEmpty {
                    ContentUnavailableView(
                        "No Prints", systemImage: "printer",
                        description: Text("Prints from this Game appear here.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                            ForEach(shown) { item in cell(item) }
                        }
                        .padding()
                        Text("The newest \(Capture.keepCount) prints are kept. Older ones go to Recently Deleted; pinned prints stay.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Captures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if printingBuilds.count > 1 || (printingBuilds.count == 1 && model.items.contains { $0.capture.buildID == nil }) {
                    ToolbarItem(placement: .topBarLeading) {
                        Picker("Build", selection: $buildFilter) {
                            Text("All Builds").tag(UUID?.none)
                            ForEach(printingBuilds) { build in Text(build.displayName).tag(Optional(build.id)) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .task { await model.load() }
            .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in
                Task { await model.load() }
            }
            .sheet(item: $opened) { item in
                PrinterPreview(slips: [item.slip], gameArtworkURL: model.artworkURL(), keeping: .captured)
            }
            .alert("Couldn’t Update Prints", isPresented: Binding(
                get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func cell(_ item: CapturedPrint) -> some View {
        Button { opened = item } label: {
            ZStack(alignment: .topTrailing) {
                PrintThumbnailView(image: item.thumbnail)
                if item.capture.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .padding(4)
                        .background(.thinMaterial, in: Circle())
                        .padding(4)
                        .accessibilityLabel("Pinned")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Print, \(item.capture.createdAt.formatted(date: .abbreviated, time: .shortened))"))
        .contextMenu {
            Button(item.capture.isPinned ? "Unpin" : "Pin", systemImage: item.capture.isPinned ? "pin.slash" : "pin") {
                Task { await model.setPinned(!item.capture.isPinned, item) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.delete(item) }
            }
        }
    }
}

/// A print's thumbnail on paper-white, keeping its pixel grid.
struct PrintThumbnailView: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "printer").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 160)
        .padding(6)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
    }
}

/// The Captures row in Game Details: the newest prints and a way into all of them. Game Details
/// loads them, since an empty section has no view to load from.
struct CapturesSection: View {
    struct Preview: Sendable {
        var recent: [CapturedPrint] = []
        var count = 0
    }

    let container: AppContainer
    let gameID: UUID
    let preview: Preview
    @State private var showsAll = false

    var body: some View {
        if preview.count > 0 {
            Section("Captures") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(preview.recent) { item in
                            PrintThumbnailView(image: item.thumbnail).frame(width: 72)
                        }
                    }
                }
                .onTapGesture { showsAll = true }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(preview.count) \(preview.count == 1 ? "print" : "prints")")
                Button(preview.count == 1 ? "Show Print" : "Show All \(preview.count) Prints") { showsAll = true }
            }
            .sheet(isPresented: $showsAll) { CapturesView(container: container, gameID: gameID) }
        }
    }

    /// The Game's newest prints for the row, read off the main thread.
    static func load(container: AppContainer, gameID: UUID) async -> Preview {
        let prints = container.printCaptures
        return await Task.detached(priority: .utility) { () -> Preview in
            guard let captures = try? prints.captures(gameID: gameID) else { return Preview() }
            let items = captures.prefix(8).compactMap { CapturedPrint.read($0, from: prints) }
            return Preview(recent: items, count: captures.count)
        }.value
    }
}
