import EmulationSession
import EmulatorDomain
import GameplayInput
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
    /// The Quick Play session whose gameplay screen is closing, shown once the cover is gone.
    @State private var closingQuickPlayID: UUID?
    @State private var endedQuickPlay: QuickPlaySession?
    @State private var quickPlayToResume: QuickPlaySession?

    var body: some View {
        Group {
            if let container = bootstrap.container {
                LibraryView(
                    container: container,
                    onPlay: { context in launch(context, container: container) },
                    onQuickPlay: { request in quickPlay(request, container: container) },
                    onResumeQuickPlay: { session in resumeQuickPlay(session, container: container) }
                )
            } else {
                ContentUnavailableView {
                    Label("\(AppBrand.displayName) Couldn’t Start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(bootstrap.errorDescription ?? "The library could not be opened.")
                }
            }
        }
        .fullScreenCover(item: $gameplay, onDismiss: showClosingQuickPlay) { presentation in
            GameplayViewControllerRepresentable(
                runtime: presentation.runtime,
                autoResumePolicy: presentation.autoResumePolicy,
                launchMessage: presentation.launchMessage,
                firstFrameClock: presentation.firstFrameClock,
                controlStyle: presentation.controlStyle,
                controllerTheme: bootstrap.container?.controllerTheme() ?? .matchSystem,
                soundMode: bootstrap.container?.soundMode() ?? .followSilentSwitch,
                onClose: { endGameplay(presentation) }
            )
            .ignoresSafeArea()
            // The status bar sits on the controller's body: dark text on Classic, light on Dark.
            .preferredColorScheme(bootstrap.container?.controllerTheme().colorScheme)
        }
        .sheet(item: $endedQuickPlay, onDismiss: resumeChosenQuickPlay) { session in
            if let container = bootstrap.container {
                NavigationStack {
                    QuickPlaySessionView(
                        session: session,
                        container: container,
                        onResume: { resumed in
                            quickPlayToResume = resumed
                            endedQuickPlay = nil
                        },
                        onFinished: { endedQuickPlay = nil }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Keep for Later") { endedQuickPlay = nil }
                        }
                    }
                }
                .interactiveDismissDisabled()
            }
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
                launchMessage: message,
                firstFrameClock: nil,
                controlStyle: container.controllerStyle(for: launch.context)
            )
        } catch {
            errorMessage = "Could not start the game: \(error)"
        }
    }

    private func quickPlay(_ request: QuickPlayRequest, container: AppContainer) {
        let url = request.url
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let temporary = try container.quickPlayWorkspace.start(
                romURL: url,
                copiedSaveProfileID: request.copiedSaveProfileID
            )
            try present(temporary, container: container, firstFrameClock: request.chosenAt)
        } catch {
            errorMessage = "Could not start Quick Play: \(error)"
        }
    }

    /// A kept session picks up from its autosave, so there is no first-frame time to report.
    private func resumeQuickPlay(_ session: QuickPlaySession, container: AppContainer) {
        do {
            try present(session, container: container, firstFrameClock: nil)
        } catch {
            errorMessage = "Could not resume Quick Play: \(error)"
        }
    }

    private func present(_ session: QuickPlaySession, container: AppContainer, firstFrameClock: UInt64?) throws {
        let runtime = QuickPlayRuntimeSession(session: session, coreRegistry: container.coreRegistry)
        try runtime.start()
        gameplay = GameplayPresentation(
            kind: .quickPlay(session.id),
            runtime: runtime,
            autoResumePolicy: container.quickPlayAutoResumePolicy(system: session.system),
            launchMessage: runtime.autoStateRejected
                ? "Couldn’t resume where you left off, so the game started over from its save."
                : nil,
            firstFrameClock: firstFrameClock,
            controlStyle: container.controllerStyle(system: session.system)
        )
    }

    private func showClosingQuickPlay() {
        guard let id = closingQuickPlayID else { return }
        closingQuickPlayID = nil
        endedQuickPlay = try? bootstrap.container?.quickPlayWorkspace.load(sessionID: id)
    }

    private func resumeChosenQuickPlay() {
        guard let session = quickPlayToResume, let container = bootstrap.container else { return }
        quickPlayToResume = nil
        resumeQuickPlay(session, container: container)
    }

    private func endGameplay(_ presentation: GameplayPresentation) {
        switch presentation.kind {
        case .library:
            bootstrap.container?.stopActiveSession(createAutoState: false)
        case .quickPlay(let id):
            closingQuickPlayID = id
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
    /// `DispatchTime` uptime when the file was chosen, for Quick Play's time-to-first-frame report.
    let firstFrameClock: UInt64?
    let controlStyle: TouchControlStyle
}

struct QuickPlayRequest {
    let url: URL
    let copiedSaveProfileID: UUID?
    /// `DispatchTime` uptime when the file was chosen.
    let chosenAt: UInt64
}

private extension ControllerTheme {
    /// Nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .matchSystem: nil
        case .classic: .light
        case .dark: .dark
        }
    }
}
