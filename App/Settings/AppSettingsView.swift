import AssetStorage
import EmulatorApplication
import EmulatorDomain
import Foundation
import GameplayInput
import SwiftUI

/// App-wide settings. Values are stored at the app scope, so a System, Game or Build override
/// still wins for that launch.
struct AppSettingsView: View {
    private let store: any SettingsStore
    private let integrityChecker: ManagedAssetIntegrityChecker?
    private let libraryDeletion: LibraryDeletionOperations?
    private let games: (any GameRepository)?

    @State private var skipBootAnimation: Bool
    @State private var autoResumePolicy: AutoResumePolicy
    @State private var controllerLayout: TouchControlStyle
    @State private var controllerTheme: ControllerTheme
    @State private var lcdFilter: LCDFilter
    @State private var colorCorrection: ColorCorrection
    @State private var dmgPalette: DMGPalette
    @State private var frameBlending: FrameBlending
    @State private var fastForwardSpeed: FastForwardSpeed
    @State private var fastForwardAudio: FastForwardAudio
    @State private var orientation: ScreenOrientation
    @State private var screenScaling: ScreenScaling
    @State private var tapGameForMenu: Bool
    @State private var soundMode: SoundMode
    @State private var hidesTouchControlsWithController: Bool
    @State private var touchHaptics: TouchHaptics
    @State private var errorMessage: String?
    @State private var systemSettings: SystemSettingsTarget?
    @Environment(\.dismiss) private var dismiss

    init(
        store: any SettingsStore,
        integrityChecker: ManagedAssetIntegrityChecker? = nil,
        libraryDeletion: LibraryDeletionOperations? = nil,
        games: (any GameRepository)? = nil
    ) {
        self.store = store
        self.integrityChecker = integrityChecker
        self.libraryDeletion = libraryDeletion
        self.games = games
        _skipBootAnimation = State(initialValue: Self.stored(Bool.self, .skipBootAnimation, in: store) ?? false)
        _autoResumePolicy = State(initialValue: Self.stored(AutoResumePolicy.self, .autoResumePolicy, in: store) ?? .always)
        _controllerLayout = State(initialValue: Self.stored(TouchControlStyle.self, .controllerLayout, in: store) ?? .gameBoy)
        _controllerTheme = State(initialValue: Self.stored(ControllerTheme.self, .controllerTheme, in: store) ?? .matchSystem)
        _lcdFilter = State(initialValue: Self.stored(LCDFilter.self, .lcdFilter, in: store) ?? .off)
        _colorCorrection = State(initialValue: Self.stored(ColorCorrection.self, .colorCorrection, in: store) ?? .defaultValue)
        _dmgPalette = State(initialValue: Self.stored(DMGPalette.self, .dmgPalette, in: store) ?? .defaultValue)
        _frameBlending = State(initialValue: Self.stored(FrameBlending.self, .frameBlending, in: store) ?? .off)
        _fastForwardSpeed = State(initialValue: Self.stored(FastForwardSpeed.self, .fastForwardSpeed, in: store) ?? .x2)
        _fastForwardAudio = State(initialValue: Self.stored(FastForwardAudio.self, .fastForwardAudio, in: store) ?? .muted)
        _orientation = State(initialValue: Self.stored(ScreenOrientation.self, .orientation, in: store) ?? .automatic)
        _screenScaling = State(initialValue: Self.stored(ScreenScaling.self, .screenScaling, in: store) ?? .integer)
        _tapGameForMenu = State(initialValue: Self.stored(Bool.self, .tapGameForMenu, in: store) ?? false)
        _soundMode = State(initialValue: Self.stored(SoundMode.self, .soundMode, in: store) ?? .followSilentSwitch)
        _hidesTouchControlsWithController = State(
            initialValue: Self.stored(Bool.self, .hideTouchControlsWithController, in: store) ?? true
        )
        _touchHaptics = State(initialValue: Self.stored(TouchHaptics.self, .touchHaptics, in: store) ?? .light)
    }

    var body: some View {
        NavigationStack {
            settingsForm
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $systemSettings) { target in
                ScopedSettingsView(
                    title: "\(target.system.displayName) Settings",
                    scope: .system(target.system),
                    system: target.system,
                    gameID: nil,
                    buildID: nil,
                    store: store
                )
            }
            .onChange(of: skipBootAnimation) { _, newValue in save(newValue, .skipBootAnimation) }
            .onChange(of: autoResumePolicy) { _, newValue in save(newValue, .autoResumePolicy) }
            .onChange(of: controllerLayout) { _, newValue in save(newValue, .controllerLayout) }
            .onChange(of: controllerTheme) { _, newValue in save(newValue, .controllerTheme) }
            .onChange(of: tapGameForMenu) { _, newValue in save(newValue, .tapGameForMenu) }
            .onChange(of: soundMode) { _, newValue in save(newValue, .soundMode) }
            .onChange(of: hidesTouchControlsWithController) { _, newValue in save(newValue, .hideTouchControlsWithController) }
            .onChange(of: touchHaptics) { _, newValue in save(newValue, .touchHaptics) }
        }
    }

    private var settingsForm: some View {
        formContent
        .onChange(of: lcdFilter) { _, newValue in save(newValue, .lcdFilter) }
        .onChange(of: colorCorrection) { _, newValue in save(newValue, .colorCorrection) }
        .onChange(of: dmgPalette) { _, newValue in save(newValue, .dmgPalette) }
        .onChange(of: frameBlending) { _, newValue in save(newValue, .frameBlending) }
        .onChange(of: fastForwardSpeed) { _, newValue in save(newValue, .fastForwardSpeed) }
        .onChange(of: fastForwardAudio) { _, newValue in save(newValue, .fastForwardAudio) }
        .onChange(of: orientation) { _, newValue in save(newValue, .orientation) }
        .onChange(of: screenScaling) { _, newValue in save(newValue, .screenScaling) }
    }

    private var formContent: some View {
        Form {
            Section {
                Picker("Controller Layout", selection: $controllerLayout) {
                    Text("Game Boy").tag(TouchControlStyle.gameBoy)
                    Text("Playtiles").tag(TouchControlStyle.playtiles)
                }
            } header: {
                Text("Controls")
            } footer: {
                Text("Game Boy puts the controls where they are on an original Game Boy, at its size. Playtiles fits the Playtiles controller.")
            }

            Section {
                Picker("Controller Theme", selection: $controllerTheme) {
                    Text("Match System").tag(ControllerTheme.matchSystem)
                    Text("Classic").tag(ControllerTheme.classic)
                    Text("Dark").tag(ControllerTheme.dark)
                }
            } footer: {
                Text("Match System uses Classic in Light Mode and Dark in Dark Mode.")
            }

            Section {
                Toggle("Tap Game for Menu", isOn: $tapGameForMenu)
            } footer: {
                Text("Tapping the \(AppBrand.displayName) button pauses the game and opens the menu. This adds tapping the game itself.")
            }

            Section {
                Toggle("Hide Touch Controls with a Controller", isOn: $hidesTouchControlsWithController)
            } footer: {
                Text("A touch on the screen brings them back until the controller’s next button press.")
            }

            Section {
                Picker("Touch Haptics", selection: $touchHaptics) {
                    Text("Off").tag(TouchHaptics.off)
                    Text("Light").tag(TouchHaptics.light)
                    Text("Medium").tag(TouchHaptics.medium)
                }
            } footer: {
                Text("How the on-screen buttons tap back when pressed. They stay still while a controller is in use.")
            }

            Section {
                Picker("Orientation", selection: $orientation) {
                    Text("Automatic").tag(ScreenOrientation.automatic)
                    Text("Portrait").tag(ScreenOrientation.portrait)
                    Text("Landscape").tag(ScreenOrientation.landscape)
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Automatic turns games with the phone, within its rotation lock. Playtiles always plays in portrait, and the library stays in portrait.")
            }

            Section {
                Picker("Screen Scaling", selection: $screenScaling) {
                    Text("Integer").tag(ScreenScaling.integer)
                    Text("Fill").tag(ScreenScaling.fill)
                }
            } footer: {
                Text("Integer keeps every pixel the same size. Fill makes the game as large as its frame, with pixel edges smoothed.")
            }

            Section {
                Picker("Color Correction", selection: $colorCorrection) {
                    ForEach(ColorCorrection.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } footer: {
                Text(ColorCorrection.explanation)
            }

            Section {
                Picker("DMG Palette", selection: $dmgPalette) {
                    ForEach(DMGPalette.allCases, id: \.self) { palette in
                        Text(palette.displayName).tag(palette)
                    }
                }
            } footer: {
                Text(DMGPalette.explanation)
            }

            Section {
                Picker("LCD Filter", selection: $lcdFilter) {
                    ForEach(LCDFilter.allCases, id: \.self) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
            } footer: {
                Text("LCD 1× adds a subtle pixel grid. LCD 3× adds red, green and blue subpixels. Screen size stays the same.")
            }

            Section {
                Picker("Frame Blending", selection: $frameBlending) {
                    ForEach(FrameBlending.allCases, id: \.self) { blending in
                        Text(blending.displayName).tag(blending)
                    }
                }
            } footer: {
                Text("Blend mixes each frame with the one before, as a Game Boy screen does, so sprites that flicker to look see-through stay steady. LCD Ghosting also leaves a short trail behind moving things.")
            }

            Section {
                Picker("Fast Forward Speed", selection: $fastForwardSpeed) {
                    ForEach(FastForwardSpeed.allCases, id: \.self) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }
            } footer: {
                Text("How fast Fast Forward in the game menu runs. Unlimited runs as fast as your phone can.")
            }

            Section {
                Picker("Fast Forward Audio", selection: $fastForwardAudio) {
                    ForEach(FastForwardAudio.allCases, id: \.self) { audio in
                        Text(audio.displayName).tag(audio)
                    }
                }
            } footer: {
                Text("Muted is silent while Fast Forward runs. Accelerated plays the sound sped up with the game, up to 4×. Faster speeds stay muted.")
            }

            Section {
                Toggle("Skip Boot Logo", isOn: $skipBootAnimation)
            } footer: {
                Text("Library games open on the game instead of the boot logo. Quick Play always skips it.")
            }

            Section {
                Picker("Sound", selection: $soundMode) {
                    ForEach(SoundMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } header: {
                Text("Sound")
            } footer: {
                Text("Always Off leaves music from other apps playing.")
            }

            Section {
                Picker("Resume Games", selection: $autoResumePolicy) {
                    Text("Always").tag(AutoResumePolicy.always)
                    Text("Ask").tag(AutoResumePolicy.ask)
                    Text("Never").tag(AutoResumePolicy.never)
                }
            } header: {
                Text("Playing")
            } footer: {
                Text("Whether a game picks up where you left off when you open it again or return to the app.")
            }

            Section {
                ForEach(GameSystem.allCases, id: \.self) { system in
                    Button {
                        systemSettings = SystemSettingsTarget(system: system)
                    } label: {
                        LabeledContent(system.displayName) {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Systems")
            } footer: {
                Text("Settings for every game on one system. A Game or Build can still set its own.")
            }

            if let libraryDeletion, let games {
                Section {
                    NavigationLink("Recently Deleted") {
                        RecentlyDeletedView(operations: libraryDeletion, games: games)
                    }
                }
            }

            if let integrityChecker {
                LibraryCheckSection(checker: integrityChecker)
            }

            Section {
                NavigationLink("How \(AppBrand.displayName) Works") { WelcomeView() }
                if let privacyURL = URL(string: "https://github.com/thisjustin816/press-any/blob/main/PRIVACY.md") {
                    Link("Privacy Policy", destination: privacyURL)
                }
                NavigationLink("Acknowledgements") { AcknowledgementsView() }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func save(_ value: some Encodable, _ key: SettingKey) {
        do {
            try store.set(value, key: key.rawValue, scope: .app)
            errorMessage = nil
        } catch {
            errorMessage = "Could not save the setting: \(error.localizedDescription)"
        }
    }

    private static func stored<T: Decodable>(_ type: T.Type, _ key: SettingKey, in store: any SettingsStore) -> T? {
        guard let json = try? store.valueJSON(key: key.rawValue, scope: .app) else { return nil }
        return try? JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

private struct SystemSettingsTarget: Identifiable {
    let system: GameSystem
    var id: GameSystem { system }
}
