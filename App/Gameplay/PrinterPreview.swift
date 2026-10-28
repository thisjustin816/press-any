import EmulationCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
final class PrinterPreviewController: UIHostingController<PrinterPreview>, UIAdaptivePresentationControllerDelegate {
    var onClose: (() -> Void)?
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }

    private func finish() {
        let close = onClose
        onClose = nil
        close?()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // A share sheet can cover this view without dismissing the print preview.
        if isBeingDismissed || presentingViewController == nil { finish() }
    }
}

private enum PrinterPreviewBackground: String, CaseIterable, Sendable {
    case transparent, light, dark, wood, gameArtwork, custom
    var title: String {
        switch self {
        case .transparent: "Transparent"
        case .light: "Light"
        case .dark: "Dark"
        case .wood: "Wood"
        case .gameArtwork: "Artwork"
        case .custom: "Custom"
        }
    }
    var flat: PrinterBackground {
        switch self {
        case .dark: .dark
        case .transparent: .transparent
        default: .light
        }
    }
}

struct PrinterPreview: View {
    let backgrounds = PrinterBackgroundStore()
    let slips: [PrinterSlip]
    /// The Game's library artwork file, when it has one.
    var gameArtworkURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var selected = 0
    /// The last background chosen, kept between previews and games.
    @AppStorage("printer.background") private var chosen = PrinterPreviewBackground.transparent
    @State private var thumbnails: [PrinterPreviewBackground: UIImage] = [:]
    @State private var customVersion = 0
    @State private var png: Data?
    @State private var error: String?
    @State private var shareFailed = false
    @State private var retry = 0
    @State private var photo: PhotosPickerItem?
    @State private var showImageImporter = false
    @State private var showPhotoPicker = false
    @State private var importing = false
    @State private var loadedCustom = false
    @State private var customImage: PrinterBackgroundImage?
    @State private var importError: String?
    @State private var shared: PrinterSharedImage?

    private var ordered: [PrinterSlip] { Array(slips.reversed()) }
    private var renderKey: String { "\(selected)-\(background.rawValue)-\(retry)-\(loadedCustom)" }
    private var available: [PrinterPreviewBackground] {
        PrinterPreviewBackground.allCases.filter {
            switch $0 {
            case .gameArtwork: gameArtworkURL != nil
            case .custom: customImage != nil
            default: true
            }
        }
    }
    /// The remembered choice, or Transparent where it isn't offered, as for Game Artwork in Quick Play.
    /// The remembered choice itself is kept for the next game that offers it.
    private var background: PrinterPreviewBackground { available.contains(chosen) ? chosen : .transparent }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if ordered.count > 1 {
                    Picker("Print", selection: $selected) {
                        ForEach(ordered.indices, id: \.self) { index in
                            Text("Print \(ordered.count - index)").tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(png == nil && error == nil)
                }
                if importing { ProgressView("Loading background") }
                ScrollView {
                    if let png, let image = UIImage(data: png) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel("Printed slip")
                    } else if let error {
                        VStack(spacing: 12) {
                            Text(error).foregroundStyle(.secondary)
                            Button("Try Again") { retry += 1 }
                        }
                    } else {
                        ProgressView("Preparing print")
                    }
                }
                backgroundSwatches
                Text("The last 10 prints stay here until the game closes. Save a copy to keep them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Save or Share", systemImage: "square.and.arrow.up") {
                    guard let png else { return }
                    do { shared = try PrinterSharedImage(png: png) }
                    catch { shareFailed = true }
                }
                .buttonStyle(.borderedProminent)
                .disabled(png == nil)
            }
            .padding()
            .navigationTitle("Prints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: renderKey) { await render() }
            .task(id: "\(loadedCustom)-\(customVersion)") { await loadThumbnails() }
            .task {
                let store = backgrounds
                defer { loadedCustom = true }
                do { customImage = try await Task.detached { try store.load() }.value }
                catch { importError = "The saved background could not be opened. Choose another image." }
            }
            .task(id: photo) {
                guard let photo else { return }
                importing = true
                defer { importing = false; self.photo = nil }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else { throw PrinterBackgroundStore.ImageError.invalidImage }
                    try await useCustom(data)
                } catch { importError = "Could not use this image. Choose a photo or image file under 25 MB." }
            }
            .alert("Background Unavailable", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) { importError = nil }
            } message: { Text(importError ?? "") }
            .alert("Could Not Share Print", isPresented: $shareFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The image could not be saved for sharing. Check available storage and try again.")
            }
            .sheet(item: $shared) { image in PrinterShareSheet(image: image) }
        }
    }

    /// Backgrounds as small previews, like a wallpaper picker. The last tile is the one custom slot:
    /// empty, it asks for an image; filled, it selects like the others, and touching and holding it
    /// replaces or removes the image.
    private var backgroundSwatches: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(available.filter { $0 != .custom }, id: \.self) { swatchButton($0) }
                    if customImage != nil {
                        swatchButton(.custom).contextMenu {
                            sourceButtons(photos: "Replace from Photos…", files: "Replace from Files…")
                            Button(role: .destructive) { removeCustom() } label: {
                                Label("Remove Background", systemImage: "trash")
                            }
                        }
                    } else {
                        Menu {
                            sourceButtons(photos: "From Photos…", files: "From Files…")
                        } label: {
                            swatchLabel(PrinterPreviewBackground.custom.title) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    .overlay { Image(systemName: "plus").font(.title3).foregroundStyle(.tint) }
                            }
                        }
                        .accessibilityLabel("Custom background")
                        .accessibilityHint("Choose an image from Photos or Files")
                    }
                }
                .padding(2)
            }
            .disabled(importing || !loadedCustom)
            // Each picker hangs off its own view and opens once the menu has closed, since a menu
            // took the pickers down with it before.
            .photosPicker(isPresented: $showPhotoPicker, selection: $photo, matching: .images)
            .background(Color.clear.fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image], onCompletion: importFile))
        }
    }

    private func swatchButton(_ option: PrinterPreviewBackground) -> some View {
        let isSelected = option == background
        return Button { chosen = option } label: {
            swatchLabel(option.title, isSelected: isSelected) {
                swatchFill(option)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title) background")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func swatchLabel(_ title: String, isSelected: Bool = false, @ViewBuilder tile: () -> some View) -> some View {
        VStack(spacing: 4) {
            tile()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func swatchFill(_ option: PrinterPreviewBackground) -> some View {
        switch option {
        case .transparent: Checkerboard()
        case .light: Color(white: 0.96)
        case .dark: Color(white: 0.16)
        case .wood, .gameArtwork, .custom:
            if let image = thumbnails[option] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
    }

    @ViewBuilder
    private func sourceButtons(photos: String, files: String) -> some View {
        Button { present { showPhotoPicker = true } } label: { Label(photos, systemImage: "photo") }
        Button { present { showImageImporter = true } } label: { Label(files, systemImage: "folder") }
    }

    private func loadThumbnails() async {
        let sources: [(PrinterPreviewBackground, URL?)] = [
            (.wood, Bundle.main.url(forResource: "PrinterWood", withExtension: "jpg")),
            (.gameArtwork, gameArtworkURL),
            (.custom, customImage == nil ? nil : backgrounds.customURL),
        ]
        thumbnails = await Task.detached(priority: .utility) {
            var images: [PrinterPreviewBackground: UIImage] = [:]
            for case let (option, url?) in sources {
                guard let image = UIImage(contentsOfFile: url.path), image.size.width > 0, image.size.height > 0 else { continue }
                let scale = 168 / min(image.size.width, image.size.height)
                images[option] = image.preparingThumbnail(of: CGSize(width: image.size.width * scale, height: image.size.height * scale))
            }
            return images
        }.value
    }

    /// Lets the menu finish closing before a system picker takes its place.
    private func present(_ show: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            show()
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError {
                importError = "The image could not be opened. Try another file."
            }
            return
        }
        importing = true
        Task {
            defer { importing = false }
            do {
                let data = try await Task.detached { try PrinterBackgroundStore.readFile(url) }.value
                try await useCustom(data)
            } catch { importError = "Could not use this image. Choose a photo or image file under 25 MB." }
        }
    }

    @MainActor
    private func useCustom(_ data: Data) async throws {
        let store = backgrounds
        let image = try await Task.detached { try store.save(data) }.value
        customImage = image
        customVersion += 1
        chosen = .custom
        retry += 1
    }

    private func removeCustom() {
        do {
            try backgrounds.remove()
            customImage = nil
            customVersion += 1
            if chosen == .custom { chosen = .transparent }
        } catch { importError = "Could not remove the saved background. Try again." }
    }

    @MainActor
    private func render() async {
        png = nil
        error = nil
        // A remembered Custom background can't be drawn until the saved image has loaded.
        guard loadedCustom, ordered.indices.contains(selected) else { return }
        let slip = ordered[selected]
        let background = background
        let custom = customImage
        let artworkURL = gameArtworkURL
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let image: PrinterSlipRenderer.Image
                switch background {
                case .wood: image = PrinterSlipRenderer.render(slip, image: try PrinterBackgroundStore.wood())
                case .custom:
                    guard let custom else { throw PrinterBackgroundStore.ImageError.invalidImage }
                    image = PrinterSlipRenderer.render(slip, image: custom)
                case .gameArtwork:
                    guard let artworkURL else { throw PrinterBackgroundStore.ImageError.invalidImage }
                    image = PrinterSlipRenderer.render(slip, image: try PrinterBackgroundStore.decode(PrinterBackgroundStore.readFile(artworkURL)))
                default: image = PrinterSlipRenderer.render(slip, background: background.flat)
                }
                return try PNGFrameEncoder(preservesAlpha: true).encode(EmulatorVideoFrame(
                    width: image.width, height: image.height,
                    bgra8888: image.bgra8888, emulatedNanoseconds: 0
                ))
            }.value
            try Task.checkCancellation()
            png = data
        } catch is CancellationError {
        } catch {
            self.error = "Could not prepare the image. Try again."
        }
    }
}

private final class PrinterSharedImage: Identifiable, Sendable {
    let id = UUID()
    let file: SharedGameplayScreenshot
    init(png: Data) throws { file = try SharedGameplayScreenshot(png: png, filename: "Printer Slip.png") }
}

private struct PrinterShareSheet: UIViewControllerRepresentable {
    let image: PrinterSharedImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [image.file.url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in image.file.discard() }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The usual sign for transparency: a light gray checkerboard.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            for row in 0..<Int((size.height / cell).rounded(.up)) {
                for column in 0..<Int((size.width / cell).rounded(.up)) where (row + column).isMultiple(of: 2) {
                    let square = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(square), with: .color(Color(white: 0.8)))
                }
            }
        }
        .background(Color.white)
    }
}
