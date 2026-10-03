import EmulatorDomain
import Foundation
import QuickPlay
import SwiftUI

@MainActor
final class AppBootstrap: ObservableObject {
    let container: AppContainer?
    let errorDescription: String?

    init() {
        do {
            container = try .live()
            errorDescription = nil
        } catch {
            container = nil
            errorDescription = String(describing: error)
        }
    }
}

@MainActor
struct RootView: View {
    @ObservedObject var bootstrap: AppBootstrap
    @State private var gameplay: GameplayPresentation?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let container = bootstrap.container {
                LibraryView(
                    container: container,
                    onPlay: { context in launch(context, container: container) },
                    onQuickPlayROM: { url in quickPlay(url, container: container) }
                )
            } else {
                ContentUnavailableView {
                    Label("\(AppBrand.displayName) Couldn’t Start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(bootstrap.errorDescription ?? "The library could not be opened.")
                }
            }
        }
        .fullScreenCover(item: $gameplay) { presentation in
            GameplayViewControllerRepresentable(
                runtime: presentation.runtime,
                onClose: { endGameplay(presentation) }
            )
            .ignoresSafeArea()
        }
        .alert(AppBrand.displayName, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func launch(_ context: LaunchContext, container: AppContainer) {
        do {
            let session = try container.startPermanentSession(context: context)
            gameplay = GameplayPresentation(kind: .library, runtime: session)
        } catch {
            errorMessage = "Could not start the game: \(error)"
        }
    }

    private func quickPlay(_ url: URL, container: AppContainer) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let temporary = try container.quickPlayWorkspace.start(romURL: url)
            let runtime = QuickPlayRuntimeSession(session: temporary, coreRegistry: container.coreRegistry)
            try runtime.start()
            gameplay = GameplayPresentation(kind: .quickPlay(temporary.id), runtime: runtime)
        } catch {
            errorMessage = "Could not start Quick Play: \(error)"
        }
    }

    private func endGameplay(_ presentation: GameplayPresentation) {
        if case .library = presentation.kind {
            bootstrap.container?.stopActiveSession(createAutoState: false)
        }
        gameplay = nil
    }
}

private struct GameplayPresentation: Identifiable {
    enum Kind {
        case library
        case quickPlay(UUID)
    }

    let id = UUID()
    let kind: Kind
    let runtime: any GameplayRuntime
}
