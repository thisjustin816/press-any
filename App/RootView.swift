import EmulationSession
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
    @State private var pendingResume: PreparedLaunch?

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
                autoResumePolicy: presentation.autoResumePolicy,
                launchMessage: presentation.launchMessage,
                onClose: { endGameplay(presentation) }
            )
            .ignoresSafeArea()
        }
        .alert("Resume where you left off?", isPresented: Binding(
            get: { pendingResume != nil },
            set: { if !$0 { pendingResume = nil } }
        ), presenting: pendingResume) { launch in
            Button("Resume") { start(launch, resume: true) }
            Button("Start Over") { start(launch, resume: false) }
        } message: { _ in
            Text("Start Over boots the game from its battery save. The resume point is kept.")
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
        let prepared = container.prepareLaunch(context: context)
        if prepared.autoState != nil, prepared.policy == .ask {
            pendingResume = prepared
        } else {
            start(prepared, resume: true)
        }
    }

    private func start(_ launch: PreparedLaunch, resume: Bool) {
        pendingResume = nil
        guard let container = bootstrap.container else { return }
        do {
            let restore = try container.start(launch, resume: resume)
            var message: String?
            if case .failed = restore {
                message = "Couldn’t restore where you left off, so the game started from its battery save. The resume point was kept."
            }
            gameplay = GameplayPresentation(
                kind: .library,
                runtime: launch.session,
                autoResumePolicy: launch.policy,
                launchMessage: message
            )
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
            gameplay = GameplayPresentation(
                kind: .quickPlay(temporary.id),
                runtime: runtime,
                autoResumePolicy: container.quickPlayAutoResumePolicy(system: temporary.system),
                launchMessage: nil
            )
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
    let autoResumePolicy: AutoResumePolicy
    let launchMessage: String?
}
