import EmulationSession
import EmulatorApplication
import EmulatorDomain
import GameplayInput
import Foundation
import QuickPlay
import SwiftUI
import UIKit

@MainActor
final class AppBootstrap: ObservableObject {
    let container: AppContainer?
    let errorDescription: String?

    init() {
        do {
            let live = try AppContainer.live()
            ScreenshotSeeder.seedIfRequested(live)
            container = live
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
    @State private var riskyLaunch: RiskyLaunch?
    /// The Quick Play session whose gameplay screen is closing, shown once the cover is gone.
    @State private var closingQuickPlayID: UUID?
    /// Set when the game menu's Add to Library closed the session, so its sheet opens on that step.
    @State private var closingQuickPlayAddsToLibrary = false
    @State private var endedQuickPlayAddsToLibrary = false
    @State private var endedQuickPlay: QuickPlaySession?
    @State private var quickPlayToResume: QuickPlaySession?
    @State private var queuedSharedFiles: [SharedFile] = []
    @State private var sharedFile: SharedFile?
    /// Retained until dismissal, so Quick Play can copy the ROM before receipt cleanup.
    @State private var closingSharedFile: SharedFile?
    @State private var sharedQuickPlay: QuickPlayRequest?
    /// Quick Play was chosen for a file shared mid-game, so that game closes first.
    @State private var closesGameForSharedQuickPlay = false
    /// A shared file that couldn't be received, reported over the library or over gameplay.
    @State private var sharedFileError: String?
    /// Set while a queued shared file waits for another sheet to close.
    @State private var sharedFileRetryScheduled = false

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
        .task { openScreenshotScene() }
        .onOpenURL { receiveSharedFile($0) }
        .onChange(of: pendingResume != nil || riskyLaunch != nil) { _, hasPendingLaunch in
            if !hasPendingLaunch { presentNextSharedFile() }
        }
        .sheet(item: sharedFileBinding(overGameplay: false), onDismiss: finishSharedFile) { file in
            sharedFileView(file)
        }
        .alert("Couldn’t Open the File", isPresented: sharedFileErrorBinding(overGameplay: false)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sharedFileError ?? "")
        }
        .fullScreenCover(item: $gameplay, onDismiss: showClosingQuickPlay) { presentation in
            GameplayViewControllerRepresentable(
                runtime: presentation.runtime,
                autoResumePolicy: presentation.autoResumePolicy,
                launchMessage: presentation.launchMessage,
                firstFrameClock: presentation.firstFrameClock,
                controlStyle: presentation.controlStyle,
                screenScaling: presentation.screenScaling,
                lcdFilter: presentation.lcdFilter,
                controllerTheme: bootstrap.container?.controllerTheme() ?? .matchSystem,
                tapGameForMenu: bootstrap.container?.tapGameForMenu() ?? false,
                soundMode: bootstrap.container?.soundMode() ?? .followSilentSwitch,
                hidesTouchControlsWithController: bootstrap.container?.hidesTouchControlsWithController() ?? true,
                touchHaptics: bootstrap.container?.touchHaptics() ?? .light,
                isCoveredBySheet: sharedFile != nil,
                closeRequested: closesGameForSharedQuickPlay,
                onClose: { endGameplay(presentation) },
                onAddToLibrary: presentation.isQuickPlay
                    ? {
                        closingQuickPlayAddsToLibrary = true
                        endGameplay(presentation)
                    }
                    : nil
            )
            .ignoresSafeArea()
            // The status bar sits on the controller's body: dark text on Classic, light on Dark.
            .preferredColorScheme(bootstrap.container?.controllerTheme().colorScheme)
            // The library's sheet can't show over this cover, so a file shared mid-game opens here.
            .sheet(item: sharedFileBinding(overGameplay: true), onDismiss: finishSharedFile) { file in
                sharedFileView(file)
            }
            .alert("Couldn’t Open the File", isPresented: sharedFileErrorBinding(overGameplay: true)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sharedFileError ?? "")
            }
        }
        .sheet(item: $endedQuickPlay, onDismiss: resumeChosenQuickPlay) { session in
            if let container = bootstrap.container {
                NavigationStack {
                    QuickPlaySessionView(
                        session: session,
                        container: container,
                        addsToLibrary: endedQuickPlayAddsToLibrary,
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
        .alert("This save may not work with this Build", isPresented: Binding(
            get: { riskyLaunch != nil },
            set: { if !$0 { riskyLaunch = nil } }
        ), presenting: riskyLaunch) { risky in
            Button("Play with a Copy") { chooseSave(for: risky, newSave: false) }
            Button("Start a New Save") { chooseSave(for: risky, newSave: true) }
            Button("Use “\(risky.profileName)” Anyway", role: .destructive) {
                riskyLaunch = nil
                if let container = bootstrap.container { launch(risky.context, container: container, checkSave: false) }
            }
            Button("Cancel", role: .cancel) { riskyLaunch = nil }
        } message: { risky in
            Text(risky.message)
        }
        .alert(AppBrand.displayName, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                presentNextSharedFile()
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func receiveSharedFile(_ url: URL) {
        guard let container = bootstrap.container else { return }
        do {
            queuedSharedFiles.append(try container.sharedFileInbox.receive(url))
            presentNextSharedFile()
        } catch {
            sharedFileError = error.localizedDescription
        }
    }

    private func sharedFileErrorBinding(overGameplay: Bool) -> Binding<Bool> {
        Binding(
            get: { sharedFileError != nil && (gameplay != nil) == overGameplay },
            set: { shown in
                guard !shown else { return }
                sharedFileError = nil
                presentNextSharedFile()
            }
        )
    }

    /// One shared file shows at a time: over the library, or over gameplay, which it pauses.
    private func sharedFileBinding(overGameplay: Bool) -> Binding<SharedFile?> {
        Binding(
            get: { (gameplay != nil) == overGameplay ? sharedFile : nil },
            set: { sharedFile = $0 }
        )
    }

    @ViewBuilder
    private func sharedFileView(_ file: SharedFile) -> some View {
        if let container = bootstrap.container {
            SharedFileView(
                file: file,
                container: container,
                quickPlayClosesGame: gameplay != nil,
                onFinished: { sharedFile = nil },
                onQuickPlay: { request in
                    sharedQuickPlay = request
                    sharedFile = nil
                }
            )
        }
    }

    private func presentNextSharedFile() {
        guard endedQuickPlay == nil, closingQuickPlayID == nil,
              pendingResume == nil, riskyLaunch == nil, errorMessage == nil, sharedFileError == nil,
              closingSharedFile == nil, sharedFile == nil, !queuedSharedFiles.isEmpty else { return }
        // A sheet the library or Game Details opened, such as Import Review, may hold work in
        // progress, so the file waits for it to close.
        guard !hasOtherPresentation else {
            guard !sharedFileRetryScheduled else { return }
            sharedFileRetryScheduled = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                sharedFileRetryScheduled = false
                presentNextSharedFile()
            }
            return
        }
        let next = queuedSharedFiles.removeFirst()
        closingSharedFile = next
        sharedFile = next
    }

    /// Whether something other than RootView's own presentations is on screen: anything above the
    /// library, or above the game while one is running. Those sheets aren't RootView state, so UIKit
    /// is the one place that knows about them.
    private var hasOtherPresentation: Bool {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        let library = root?.presentedViewController
        return gameplay == nil ? library != nil : library?.presentedViewController != nil
    }

    private func finishSharedFile() {
        if sharedQuickPlay != nil, gameplay != nil {
            closesGameForSharedQuickPlay = true
            return
        }
        startSharedQuickPlay()
        presentNextSharedFile()
    }

    /// Starts Quick Play chosen for a shared file, then lets the file's receipt go. Quick Play
    /// copies the ROM first, so the receipt has to outlive it.
    private func startSharedQuickPlay() {
        guard let container = bootstrap.container else { return }
        if let request = sharedQuickPlay {
            sharedQuickPlay = nil
            quickPlay(request, container: container)
        }
        if let file = closingSharedFile {
            container.sharedFileInbox.discard(file)
            closingSharedFile = nil
        }
    }

    private func launch(_ context: LaunchContext, container: AppContainer, checkSave: Bool = true) {
        // A failed check never blocks play; it only withholds a warning it couldn't confirm.
        if checkSave, let assessment = try? container.saveCompatibility.execute(context: context), assessment.isRisky,
           let profile = try? container.repositories.saveProfiles.fetchSaveProfile(id: context.saveProfileID) {
            riskyLaunch = RiskyLaunch(context: context, assessment: assessment, profileName: profile.displayName)
            return
        }
        let prepared = container.prepareLaunch(context: context)
        if prepared.autoState != nil, prepared.policy == .ask {
            pendingResume = prepared
        } else {
            start(prepared, resume: true)
        }
    }

    /// The gameplay and Quick Play scenes; `LibraryView` opens the rest.
    private func openScreenshotScene() {
        guard let container = bootstrap.container else { return }
        switch ScreenshotScene.current {
        case .play(let file):
            do {
                guard let context = try ScreenshotScene.launchContext(romFile: file, in: container) else {
                    errorMessage = "\(file) wasn’t seeded."
                    return
                }
                launch(context, container: container)
            } catch {
                errorMessage = "Could not start \(file): \(error)"
            }
        case .quickPlayInfo(let file):
            do {
                endedQuickPlay = try container.quickPlayWorkspace.start(romURL: ScreenshotScene.romURL(file))
            } catch {
                errorMessage = "Couldn’t start Quick Play: \(error.localizedDescription)"
            }
        case .quickPlay(let file):
            quickPlay(
                QuickPlayRequest(
                    url: ScreenshotScene.romURL(file),
                    copiedSaveProfileID: nil,
                    chosenAt: DispatchTime.now().uptimeNanoseconds
                ),
                container: container
            )
        default:
            break
        }
    }

    private func chooseSave(for risky: RiskyLaunch, newSave: Bool) {
        riskyLaunch = nil
        guard let container = bootstrap.container else { return }
        do {
            let context = newSave
                ? try container.chooseSaveForBuild.playWithNewSave(risky.context)
                : try container.chooseSaveForBuild.playWithCopy(risky.context)
            launch(context, container: container, checkSave: false)
        } catch {
            errorMessage = "Could not make the save: \(error.localizedDescription)"
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
                controlStyle: container.controllerStyle(for: launch.context),
                screenScaling: container.screenScaling(for: launch.context),
                lcdFilter: container.lcdFilter(for: launch.context)
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
            errorMessage = "Couldn’t start Quick Play: \(error.localizedDescription)"
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
        let runtime = QuickPlayRuntimeSession(
            session: session,
            coreRegistry: container.coreRegistry,
            assetStore: container.fileStore
        )
        try runtime.start()
        gameplay = GameplayPresentation(
            kind: .quickPlay(session.id),
            runtime: runtime,
            autoResumePolicy: container.quickPlayAutoResumePolicy(system: session.system),
            launchMessage: runtime.autoStateRejected
                ? "Couldn’t resume where you left off, so the game started over from its save."
                : nil,
            firstFrameClock: firstFrameClock,
            controlStyle: container.controllerStyle(system: session.system),
            screenScaling: container.screenScaling(system: session.system),
            lcdFilter: container.lcdFilter(system: session.system)
        )
    }

    private func showClosingQuickPlay() {
        guard let id = closingQuickPlayID else {
            startSharedQuickPlay()
            presentNextSharedFile()
            return
        }
        closingQuickPlayID = nil
        let addsToLibrary = closingQuickPlayAddsToLibrary
        closingQuickPlayAddsToLibrary = false
        guard let container = bootstrap.container else { return }
        do {
            endedQuickPlayAddsToLibrary = addsToLibrary
            endedQuickPlay = try container.quickPlayWorkspace.load(sessionID: id)
        } catch {
            endedQuickPlayAddsToLibrary = false
            // Its sheet won't show, so a shared ROM waiting on it is dropped and its receipt let go.
            sharedQuickPlay = nil
            startSharedQuickPlay()
            errorMessage = "Couldn’t reopen the Quick Play session: \(error.localizedDescription)"
        }
    }

    /// After a Quick Play session's sheet. Resuming that session drops a shared file's pending
    /// Quick Play, since the player chose the earlier game instead.
    private func resumeChosenQuickPlay() {
        guard let session = quickPlayToResume, let container = bootstrap.container else {
            startSharedQuickPlay()
            presentNextSharedFile()
            return
        }
        quickPlayToResume = nil
        sharedQuickPlay = nil
        startSharedQuickPlay()
        resumeQuickPlay(session, container: container)
    }

    private func endGameplay(_ presentation: GameplayPresentation) {
        closesGameForSharedQuickPlay = false
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
    let screenScaling: ScreenScaling
    let lcdFilter: LCDFilter

    var isQuickPlay: Bool {
        if case .quickPlay = kind { return true }
        return false
    }
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

/// A launch held back because its save was last written by another Build that may lay it out
/// differently.
private struct RiskyLaunch {
    let context: LaunchContext
    let assessment: SaveCompatibilityAssessment
    let profileName: String

    var message: String {
        var lines = ["“\(profileName)” was last saved by \(assessment.writtenBy?.displayName ?? "another Build")."]
        for risk in assessment.risks {
            switch risk {
            case .gbStudio:
                lines.append("A GB Studio game can lay out its saved data differently from one Build to the next, even with the same GB Studio version.")
            case .differentTools(let writtenWith, let playingWith):
                lines.append("That Build was made with \(Self.list(writtenWith)); this one with \(Self.list(playingWith)).")
            case .differentSaveHardware:
                lines.append("The two Builds declare different save hardware in their cartridge headers.")
            }
        }
        lines.append("A copy keeps the original save safe.")
        return lines.joined(separator: " ")
    }

    private static func list(_ tools: [String]) -> String {
        tools.isEmpty ? "unrecognized tools" : tools.formatted(.list(type: .and))
    }
}
