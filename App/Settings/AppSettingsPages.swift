import EmulatorApplication
import EmulatorDomain
import Foundation
import GameplayInput
import SwiftUI

/// Reads and writes settings at the app scope for the pages under App Settings.
struct AppSettingsStorage {
    let store: any SettingsStore

    func value<T: Decodable>(_ type: T.Type, _ key: SettingKey) -> T? {
        guard let json = try? store.valueJSON(key: key.rawValue, scope: .app) else { return nil }
        return try? JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// Saves the value, returning the message to show when it can't be saved.
    func save(_ value: some Encodable, _ key: SettingKey) -> String? {
        do {
            try store.set(value, key: key.rawValue, scope: .app)
            return nil
        } catch {
            return "Could not save the setting: \(error.localizedDescription)"
        }
    }
}

/// How the game is controlled, by touch or with a controller.
struct ControlsSettingsPage: View {
    private let storage: AppSettingsStorage

    @State private var controllerLayout: TouchControlStyle
    @State private var controllerTheme: ControllerTheme
    @State private var touchHaptics: TouchHaptics
    @State private var tapGameForMenu: Bool
    @State private var hidesTouchControlsWithController: Bool
    @State private var errorMessage: String?

    init(storage: AppSettingsStorage) {
        self.storage = storage
        _controllerLayout = State(initialValue: storage.value(TouchControlStyle.self, .controllerLayout) ?? .gameBoy)
        _controllerTheme = State(initialValue: storage.value(ControllerTheme.self, .controllerTheme) ?? .matchSystem)
        _touchHaptics = State(initialValue: storage.value(TouchHaptics.self, .touchHaptics) ?? .light)
        _tapGameForMenu = State(initialValue: storage.value(Bool.self, .tapGameForMenu) ?? false)
        _hidesTouchControlsWithController = State(
            initialValue: storage.value(Bool.self, .hideTouchControlsWithController) ?? true
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Controller Layout", selection: $controllerLayout) {
                    Text("Game Boy").tag(TouchControlStyle.gameBoy)
                    Text("Playtiles").tag(TouchControlStyle.playtiles)
                }
                Picker("Controller Theme", selection: $controllerTheme) {
                    Text("Match System").tag(ControllerTheme.matchSystem)
                    Text("Classic").tag(ControllerTheme.classic)
                    Text("Dark").tag(ControllerTheme.dark)
                }
            } footer: {
                Text("Game Boy puts the controls where they are on an original Game Boy, at its size. Playtiles fits the Playtiles controller. Match System uses Classic in Light Mode and Dark in Dark Mode.")
            }

            Section {
                Picker("Touch Haptics", selection: $touchHaptics) {
                    Text("Off").tag(TouchHaptics.off)
                    Text("Light").tag(TouchHaptics.light)
                    Text("Medium").tag(TouchHaptics.medium)
                }
                Toggle("Tap Game for Menu", isOn: $tapGameForMenu)
            } header: {
                Text("Touch")
            } footer: {
                Text("Touch Haptics is how the on-screen buttons tap back when pressed. Tap Game for Menu lets a tap on the game open the menu, as the \(AppBrand.displayName) button does.")
            }

            Section {
                Toggle("Hide Touch Controls", isOn: $hidesTouchControlsWithController)
            } header: {
                Text("With a Controller")
            } footer: {
                Text("A touch on the screen brings them back until the controller’s next button press. Haptics stay off while a controller is in use.")
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Controls")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: controllerLayout) { _, newValue in save(newValue, .controllerLayout) }
        .onChange(of: controllerTheme) { _, newValue in save(newValue, .controllerTheme) }
        .onChange(of: touchHaptics) { _, newValue in save(newValue, .touchHaptics) }
        .onChange(of: tapGameForMenu) { _, newValue in save(newValue, .tapGameForMenu) }
        .onChange(of: hidesTouchControlsWithController) { _, newValue in save(newValue, .hideTouchControlsWithController) }
    }

    private func save(_ value: some Encodable, _ key: SettingKey) {
        errorMessage = storage.save(value, key)
    }
}

/// How the game picture looks. Screen Colors depends on the system, so it lives under Systems.
struct DisplaySettingsPage: View {
    private let storage: AppSettingsStorage
    @ObservedObject private var plus: PlusStore

    @State private var showsPlus = false
    @State private var orientation: ScreenOrientation
    @State private var screenScaling: ScreenScaling
    @State private var lcdFilter: LCDFilter
    @State private var frameBlending: FrameBlending
    @State private var errorMessage: String?

    init(storage: AppSettingsStorage, plus: PlusStore) {
        self.storage = storage
        _plus = ObservedObject(wrappedValue: plus)
        _orientation = State(initialValue: storage.value(ScreenOrientation.self, .orientation) ?? .automatic)
        _screenScaling = State(initialValue: storage.value(ScreenScaling.self, .screenScaling) ?? .integer)
        _lcdFilter = State(initialValue: storage.value(LCDFilter.self, .lcdFilter) ?? .off)
        _frameBlending = State(initialValue: storage.value(FrameBlending.self, .frameBlending) ?? .off)
    }

    var body: some View {
        Form {
            Section {
                Picker("Orientation", selection: $orientation) {
                    Text("Automatic").tag(ScreenOrientation.automatic)
                    Text("Portrait").tag(ScreenOrientation.portrait)
                    Text("Landscape").tag(ScreenOrientation.landscape)
                }
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
                Picker(selection: Binding(get: { lcdFilter }, set: { chooseLCDFilter($0) })) {
                    ForEach(LCDFilter.allCases, id: \.self) { filter in
                        Text(plus.gate.label(filter.displayName, needsPlus: filter.needsPlus)).tag(filter)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("LCD Filter")
                        if !plus.isUnlocked { PlusBadge() }
                    }
                }
                Picker("Frame Blending", selection: $frameBlending) {
                    ForEach(FrameBlending.allCases, id: \.self) { blending in
                        Text(blending.displayName).tag(blending)
                    }
                }
            } header: {
                Text("Effects")
            } footer: {
                Text(Self.effectsFooter(plus.gate))
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Display")
        .navigationBarTitleDisplayMode(.inline)
        .plusSheet(isPresented: $showsPlus, store: plus)
        .onChange(of: orientation) { _, newValue in save(newValue, .orientation) }
        .onChange(of: screenScaling) { _, newValue in save(newValue, .screenScaling) }
        .onChange(of: lcdFilter) { _, newValue in save(newValue, .lcdFilter) }
        .onChange(of: frameBlending) { _, newValue in save(newValue, .frameBlending) }
    }

    static func effectsFooter(_ gate: PlusGate) -> String {
        let effects = "LCD 1× adds a subtle pixel grid and LCD 3× red, green and blue subpixels, at the same screen size. Blend mixes each frame with the one before, as a Game Boy screen does, so sprites that flicker to look see-through stay steady. LCD Ghosting also leaves a short trail behind moving things."
        guard gate.isLocked(true) else { return effects }
        return effects + " LCD filters come with \(PlusProduct.name). Without it a game shows Off, and a filter you already chose is kept."
    }

    /// A Plus filter without Plus opens the Plus screen and leaves the choice as it was.
    private func chooseLCDFilter(_ filter: LCDFilter) {
        if plus.gate.isLocked(filter.needsPlus) {
            showsPlus = true
        } else {
            lcdFilter = filter
        }
    }

    private func save(_ value: some Encodable, _ key: SettingKey) {
        errorMessage = storage.save(value, key)
    }
}

/// Sound, speed and how games start and pick up again.
struct PlayingSettingsPage: View {
    private let storage: AppSettingsStorage
    @ObservedObject private var plus: PlusStore

    @State private var showsPlus = false

    @State private var soundMode: SoundMode
    @State private var fastForwardSpeed: FastForwardSpeed
    @State private var fastForwardAudio: FastForwardAudio
    @State private var autoResumePolicy: AutoResumePolicy
    @State private var skipBootAnimation: Bool
    @State private var saveStateSlots: SaveStateSlots
    @State private var nameNewStates: Bool
    @State private var keepSaveStates: KeepSaveStates
    @State private var keepAutoStates: KeepAutoStates
    @State private var errorMessage: String?

    init(storage: AppSettingsStorage, plus: PlusStore) {
        self.storage = storage
        _plus = ObservedObject(wrappedValue: plus)
        _saveStateSlots = State(initialValue: storage.value(SaveStateSlots.self, .saveStateSlots) ?? .off)
        _nameNewStates = State(initialValue: storage.value(Bool.self, .nameNewStates) ?? false)
        _keepSaveStates = State(initialValue: storage.value(KeepSaveStates.self, .keepSaveStates) ?? .all)
        _keepAutoStates = State(initialValue: storage.value(KeepAutoStates.self, .keepAutoStates) ?? .five)
        _soundMode = State(initialValue: storage.value(SoundMode.self, .soundMode) ?? .followSilentSwitch)
        _fastForwardSpeed = State(initialValue: storage.value(FastForwardSpeed.self, .fastForwardSpeed) ?? .x2)
        _fastForwardAudio = State(initialValue: storage.value(FastForwardAudio.self, .fastForwardAudio) ?? .muted)
        _autoResumePolicy = State(initialValue: storage.value(AutoResumePolicy.self, .autoResumePolicy) ?? .always)
        _skipBootAnimation = State(initialValue: storage.value(Bool.self, .skipBootAnimation) ?? false)
    }

    var body: some View {
        Form {
            Section {
                Picker("Sound", selection: $soundMode) {
                    ForEach(SoundMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            } footer: {
                Text("Always Off leaves music from other apps playing. The game menu changes this too.")
            }

            Section {
                Picker("Speed", selection: $fastForwardSpeed) {
                    ForEach(FastForwardSpeed.allCases, id: \.self) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }
                Picker("Audio", selection: $fastForwardAudio) {
                    ForEach(FastForwardAudio.allCases, id: \.self) { audio in
                        Text(audio.displayName).tag(audio)
                    }
                }
            } header: {
                Text("Fast Forward")
            } footer: {
                Text("Unlimited runs as fast as your phone can. Muted is silent while Fast Forward runs; Accelerated plays the sound sped up with the game, up to 4×, and faster speeds stay muted.")
            }

            Section {
                Picker("Resume Games", selection: $autoResumePolicy) {
                    Text("Always").tag(AutoResumePolicy.always)
                    Text("Ask").tag(AutoResumePolicy.ask)
                    Text("Never").tag(AutoResumePolicy.never)
                }
                Toggle("Skip Boot Logo", isOn: $skipBootAnimation)
            } footer: {
                Text("Resume Games picks up where you left off when you open a game again or return to the app. Skip Boot Logo opens library games on the game; Quick Play always skips it.")
            }

            Section {
                Picker("Slots", selection: $saveStateSlots) {
                    ForEach(SaveStateSlots.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Name New States", isOn: $nameNewStates)
                Picker("Keep Save States", selection: $keepSaveStates) {
                    ForEach(KeepSaveStates.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                keepAutoStatesControl
            } header: {
                Text("Save States")
            } footer: {
                Text(Self.saveStatesFooter(plus.gate))
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Playing")
        .navigationBarTitleDisplayMode(.inline)
        .plusSheet(isPresented: $showsPlus, store: plus)
        .onChange(of: saveStateSlots) { _, newValue in save(newValue, .saveStateSlots) }
        .onChange(of: nameNewStates) { _, newValue in save(newValue, .nameNewStates) }
        .onChange(of: keepSaveStates) { _, newValue in save(newValue, .keepSaveStates) }
        .onChange(of: keepAutoStates) { _, newValue in save(newValue, .keepAutoStates) }
        .onChange(of: soundMode) { _, newValue in save(newValue, .soundMode) }
        .onChange(of: fastForwardSpeed) { _, newValue in save(newValue, .fastForwardSpeed) }
        .onChange(of: fastForwardAudio) { _, newValue in save(newValue, .fastForwardAudio) }
        .onChange(of: autoResumePolicy) { _, newValue in save(newValue, .autoResumePolicy) }
        .onChange(of: skipBootAnimation) { _, newValue in save(newValue, .skipBootAnimation) }
    }

    /// Without Plus the newest Auto State is kept, so the row shows 1 and each number opens the
    /// Plus screen. The stored choice is left alone for when Plus returns.
    @ViewBuilder private var keepAutoStatesControl: some View {
        if plus.gate.isLocked(keepAutoStates.needsPlus) {
            Menu {
                ForEach(KeepAutoStates.allCases, id: \.self) { keep in
                    Button(plus.gate.label(keep.displayName, needsPlus: keep.needsPlus)) { showsPlus = true }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Keep Auto States")
                        .foregroundStyle(Color.primary)
                    PlusBadge()
                    Spacer()
                    Text(String(plus.gate.keptAutoStates(keepAutoStates)))
                        .foregroundStyle(Color.secondary)
                }
            }
            .accessibilityLabel("Keep Auto States")
            .accessibilityValue("\(plus.gate.keptAutoStates(keepAutoStates)), Plus feature")
        } else {
            Picker("Keep Auto States", selection: $keepAutoStates) {
                ForEach(KeepAutoStates.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
    }

    static func saveStatesFooter(_ gate: PlusGate) -> String {
        let cleanup = "Pinned states are never cleaned up. Cleaned-up save states go to Recently Deleted. Auto States are removed permanently. Changes apply after the next save of that kind."
        guard gate.isLocked(KeepAutoStates.five.needsPlus) else { return cleanup }
        return "Without Plus, \(AppBrand.displayName) keeps your latest Auto State. " + cleanup
    }

    private func save(_ value: some Encodable, _ key: SettingKey) {
        errorMessage = storage.save(value, key)
    }
}
