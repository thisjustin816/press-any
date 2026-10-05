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

    @State private var skipBootAnimation: Bool
    @State private var autoResumePolicy: AutoResumePolicy
    @State private var controllerLayout: TouchControlStyle
    @State private var controllerTheme: ControllerTheme
    @State private var screenScaling: ScreenScaling
    @State private var tapGameForMenu: Bool
    @State private var soundMode: SoundMode
    @State private var hidesTouchControlsWithController: Bool
    @State private var touchHaptics: TouchHaptics
    @State private var errorMessage: String?
    @State private var systemSettings: SystemSettingsTarget?
    @Environment(\.dismiss) private var dismiss

    init(store: any SettingsStore, integrityChecker: ManagedAssetIntegrityChecker? = nil) {
        self.store = store
        self.integrityChecker = integrityChecker
        _skipBootAnimation = State(initialValue: Self.stored(Bool.self, .skipBootAnimation, in: store) ?? false)
        _autoResumePolicy = State(initialValue: Self.stored(AutoResumePolicy.self, .autoResumePolicy, in: store) ?? .always)
        _controllerLayout = State(initialValue: Self.stored(TouchControlStyle.self, .controllerLayout, in: store) ?? .gameBoy)
        _controllerTheme = State(initialValue: Self.stored(ControllerTheme.self, .controllerTheme, in: store) ?? .matchSystem)
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
                    Text("Tapping \(AppBrand.displayName) at the bottom of the screen always opens the game menu. This adds tapping the game itself.")
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
                    Picker("Screen Scaling", selection: $screenScaling) {
                        Text("Integer").tag(ScreenScaling.integer)
                        Text("Fill").tag(ScreenScaling.fill)
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Integer keeps every pixel the same size. Fill makes the game as large as its frame, with pixel edges smoothed.")
                }

                Section {
                    Toggle("Skip Boot Logo", isOn: $skipBootAnimation)
                } footer: {
                    Text("Library games open on the game instead of the boot logo. Quick Play always skips it.")
                }

                Section {
                    Picker("Sound", selection: $soundMode) {
                        Text("Follow Silent Switch").tag(SoundMode.followSilentSwitch)
                        Text("Always On").tag(SoundMode.alwaysOn)
                        Text("Always Off").tag(SoundMode.alwaysOff)
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

                if let integrityChecker {
                    LibraryCheckSection(checker: integrityChecker)
                }

                Section {
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
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
            .onChange(of: screenScaling) { _, newValue in save(newValue, .screenScaling) }
            .onChange(of: tapGameForMenu) { _, newValue in save(newValue, .tapGameForMenu) }
            .onChange(of: soundMode) { _, newValue in save(newValue, .soundMode) }
            .onChange(of: hidesTouchControlsWithController) { _, newValue in save(newValue, .hideTouchControlsWithController) }
            .onChange(of: touchHaptics) { _, newValue in save(newValue, .touchHaptics) }
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
