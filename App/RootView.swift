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
    @State private var damagedSave: DamagedSaveLaunch?
    /// The Quick Play session whose gameplay screen is closing, shown once the cover is gone.
    @State private var closingQuickPlayID: UUID?
    /// Set when the game menu's Add to Library closed the session, so its sheet opens on that step.
    @State private var closingQuickPlayAddsToLibrary = false
    @State private var endedQuickPlayAddsToLibrary = false
    @State private var endedQuickPlay: QuickPlaySession?
    @State private var quickPlayToResume: QuickPlaySession?
    /// Shared files in arrival order, with any that couldn't be received, each shown in turn.
    @State private var queuedSharedFiles: [SharedArrival] = []
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
    /// The open game's settings, from its menu.
    @State private var showsGameplaySettings = false
    @State private var showsWelcome = false

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
        .task {
            openScreenshotScene()
            showWelcomeIfNeeded()
        }
        .onOpenURL { receiveSharedFile($0) }
        .onChange(of: gameplayOrientations, initial: true) { _, mask in
            GameplayOrientation.update(mask)
        }
        .onChange(of: pendingResume != nil || riskyLaunch != nil || damagedSave != nil) { _, hasPendingLaunch in
            if !hasPendingLaunch { presentNextSharedFile() }
        }
        .sheet(item: sharedFileBinding(overGameplay: false), onDismiss: finishSharedFile) { file in
            sharedFileView(file)
        }
        .sheet(isPresented: $showsWelcome, onDismiss: {
            WelcomeScreen.markShown()
            presentNextSharedFile()
        }) {
            NavigationStack {
                WelcomeView { showsWelcome = false }
            }
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
                display: presentation.display,
                controllerTheme: bootstrap.container?.controllerTheme() ?? .matchSystem,
                tapGameForMenu: bootstrap.container?.tapGameForMenu() ?? false,
                soundMode: bootstrap.container?.soundMode() ?? .followSilentSwitch,
                hidesTouchControlsWithController: bootstrap.container?.hidesTouchControlsWithController() ?? true,
                touchHaptics: bootstrap.container?.touchHaptics() ?? .light,
                isCoveredBySheet: sharedFile != nil || showsGameplaySettings,
                closeRequested: closesGameForSharedQuickPlay,
                onClose: { endGameplay(presentation) },
                onAddToLibrary: presentation.isQuickPlay
                    ? {
                        closingQuickPlayAddsToLibrary = true
                        endGameplay(presentation)
                    }
                    : nil,
                onOpenSettings: presentation.settings == nil ? nil : { showsGameplaySettings = true }
            )
            .ignoresSafeArea()
            // The status bar sits on the controller's body: dark text on Classic, light on Dark.
            .preferredColorScheme(bootstrap.container?.controllerTheme().colorScheme)
            .sheet(isPresented: $showsGameplaySettings, onDismiss: presentNextSharedFile) {
                gameplaySettingsView(presentation)
            }
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
        .alert("“\(damagedSave?.profileName ?? "")” May Be Damaged", isPresented: Binding(
            get: { damagedSave != nil },
            set: { if !$0 { damagedSave = nil } }
        ), presenting: damagedSave) { damaged in
            Button("Use It Anyway", role: .destructive) { acceptDamagedSave(damaged) }
            Button("Start a New Save") { startNewSave(for: damaged) }
            Button("Cancel", role: .cancel) { damagedSave = nil }
        } message: { _ in
            Text("Its save file changed after \(AppBrand.displayName) last wrote it. It may be damaged, or the app may have closed while saving. Use It Anyway keeps a copy of the file as it is first. Replace Save from File in the game’s Save Profiles can bring in another.")
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

    /// A launch that opened a shared file or a game goes straight to it, and the welcome waits for
    /// the next launch.
    private func showWelcomeIfNeeded() {
        guard bootstrap.container != nil, WelcomeScreen.showsAtLaunch(),
              gameplay == nil, sharedFile == nil, queuedSharedFiles.isEmpty else { return }
        showsWelcome = true
    }

    private func receiveSharedFile(_ url: URL) {
        guard let container = bootstrap.container else { return }
        do {
            queuedSharedFiles.append(.file(try container.sharedFileInbox.receive(url)))
        } catch {
            // Reported when nothing else is on screen, as a file would be shown.
            queuedSharedFiles.append(.failure(error.localizedDescription))
        }
        presentNextSharedFile()
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

    private var gameplayOrientations: UIInterfaceOrientationMask {
        GameplayOrientation.mask(
            style: gameplay?.display.controlStyle,
            orientation: gameplay?.display.orientation ?? .automatic,
            coveredBySheet: showsGameplaySettings || sharedFile != nil || sharedFileError != nil
        )
    }

    /// One shared file shows at a time: over the library, or over gameplay, which it pauses.
    private func sharedFileBinding(overGameplay: Bool) -> Binding<SharedFile?> {
        Binding(
            get: { (gameplay != nil) == overGameplay ? sharedFile : nil },
            set: { sharedFile = $0 }
        )
    }

    /// The open game's settings, at half height so the paused game shows each change above it.
    @ViewBuilder
    private func gameplaySettingsView(_ presentation: GameplayPresentation) -> some View {
        if let container = bootstrap.container, let target = presentation.settings {
            ScopedSettingsView(
                title: target.title,
                scope: target.scope,
                system: target.system,
                gameID: target.gameID,
                buildID: target.buildID,
                store: container.repositories.settings,
                onChange: {
                    // The cover's item keeps its identity, so the game updates in place.
                    gameplay?.display = container.gameplayDisplay(for: target)
                }
            )
            .presentationDetents([.medium, .large])
        }
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
              pendingResume == nil, riskyLaunch == nil, damagedSave == nil, errorMessage == nil, sharedFileError == nil,
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
        switch queuedSharedFiles.removeFirst() {
        case .file(let next):
            closingSharedFile = next
            sharedFile = next
        case .failure(let message):
            sharedFileError = message
        }
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

    /// Records the save file as it is, after keeping a copy of it, and starts the game with it.
    private func acceptDamagedSave(_ damaged: DamagedSaveLaunch) {
        damagedSave = nil
        guard let container = bootstrap.container else { return }
        do {
            try container.acceptDamagedSave.execute(profileID: damaged.context.saveProfileID)
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            launch(damaged.context, container: container, checkSave: false)
        } catch {
            errorMessage = "Couldn’t use the save: \(error.localizedDescription)"
        }
    }

    private func startNewSave(for damaged: DamagedSaveLaunch) {
        damagedSave = nil
        guard let container = bootstrap.container else { return }
        do {
            let context = try container.chooseSaveForBuild.playWithNewSave(damaged.context)
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
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
                settings: container.gameplaySettingsTarget(for: launch.context),
                display: GameplayDisplaySettings(
                    controlStyle: container.controllerStyle(for: launch.context),
                    orientation: container.orientation(for: launch.context),
                    screenScaling: container.screenScaling(for: launch.context),
                    lcdFilter: container.lcdFilter(for: launch.context),
                    colorCorrection: container.colorCorrection(for: launch.context),
                    dmgPalette: container.dmgPalette(for: launch.context),
                    frameBlending: container.frameBlending(for: launch.context),
                    fastForwardSpeed: container.fastForwardSpeed(for: launch.context),
                    fastForwardAudio: container.fastForwardAudio(for: launch.context)
                )
            )
        } catch PersistentSaveServiceError.hashMismatch {
            let profile = try? container.repositories.saveProfiles.fetchSaveProfile(id: launch.context.saveProfileID)
            damagedSave = DamagedSaveLaunch(context: launch.context, profileName: profile?.displayName ?? "This Save Profile")
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
            settings: container.gameplaySettingsTarget(system: session.system),
            display: container.gameplayDisplay(for: container.gameplaySettingsTarget(system: session.system))
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
        showsGameplaySettings = false
        switch presentation.kind {
        case .library:
            bootstrap.container?.stopActiveSession(createAutoState: false)
        case .quickPlay(let id):
            closingQuickPlayID = id
        }
        gameplay = nil
    }
}

private enum SharedArrival {
    case file(SharedFile)
    case failure(String)
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
    /// Where the game menu's Settings saves, or nil when the game's Build couldn't be read.
    let settings: GameplaySettingsTarget?
    /// Updated as the settings sheet changes them.
    var display: GameplayDisplaySettings

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
/// A launch stopped because its Save Profile's save file doesn't match the hash recorded when it
/// was written.
private struct DamagedSaveLaunch {
    let context: LaunchContext
    let profileName: String
}

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
