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

private enum PrinterPreviewBackground: String, Sendable {
    case transparent, light, dark, wood, custom
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
    @Environment(\.dismiss) private var dismiss
    @State private var selected = 0
    @State private var background = PrinterPreviewBackground.transparent
    @State private var png: Data?
    @State private var error: String?
    @State private var shareFailed = false
    @State private var retry = 0
    @State private var photo: PhotosPickerItem?
    @State private var showImageImporter = false
    @State private var importing = false
    @State private var loadedCustom = false
    @State private var customImage: PrinterBackgroundImage?
    @State private var importError: String?
    @State private var shared: PrinterSharedImage?

    private var ordered: [PrinterSlip] { Array(slips.reversed()) }
    private var renderKey: String { "\(selected)-\(background.rawValue)-\(retry)" }

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
                Picker("Background", selection: $background) {
                    Text("Light").tag(PrinterPreviewBackground.light)
                    Text("Dark").tag(PrinterPreviewBackground.dark)
                    Text("Transparent").tag(PrinterPreviewBackground.transparent)
                    Text("Wood").tag(PrinterPreviewBackground.wood)
                    if customImage != nil { Text("Custom").tag(PrinterPreviewBackground.custom) }
                }
                .pickerStyle(.menu)
                .disabled(png == nil && error == nil)
                Menu("Custom Background", systemImage: "photo") {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose from Photos", systemImage: "photo") }
                    Button("Choose from Files", systemImage: "folder") { showImageImporter = true }
                    if customImage != nil {
                        Button("Remove Custom Background", systemImage: "trash", role: .destructive) { removeCustom() }
                    }
                }
                .disabled(importing || !loadedCustom)
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
            .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image]) { result in
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

    @MainActor
    private func useCustom(_ data: Data) async throws {
        let store = backgrounds
        let image = try await Task.detached { try store.save(data) }.value
        customImage = image
        background = .custom
        retry += 1
    }

    private func removeCustom() {
        do {
            try backgrounds.remove()
            customImage = nil
            if background == .custom { background = .transparent }
        } catch { importError = "Could not remove the saved background. Try again." }
    }

    @MainActor
    private func render() async {
        png = nil
        error = nil
        guard ordered.indices.contains(selected) else { return }
        let slip = ordered[selected]
        let background = background
        let custom = customImage
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let image: PrinterSlipRenderer.Image
                switch background {
                case .wood: image = PrinterSlipRenderer.render(slip, image: try PrinterBackgroundStore.wood())
                case .custom:
                    guard let custom else { throw PrinterBackgroundStore.ImageError.invalidImage }
                    image = PrinterSlipRenderer.render(slip, image: custom)
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
