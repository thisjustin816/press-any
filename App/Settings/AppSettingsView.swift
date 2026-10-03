import EmulatorApplication
import EmulatorDomain
import Foundation
import GameplayInput
import SwiftUI

/// App-wide settings. Values are stored at the app scope, so a System, Game or Build override
/// still wins for that launch.
struct AppSettingsView: View {
    private let store: any SettingsStore

    @State private var skipBootAnimation: Bool
    @State private var autoResumePolicy: AutoResumePolicy
    @State private var controllerLayout: TouchControlStyle
    @State private var soundMode: SoundMode
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(store: any SettingsStore) {
        self.store = store
        _skipBootAnimation = State(initialValue: Self.stored(Bool.self, .skipBootAnimation, in: store) ?? false)
        _autoResumePolicy = State(initialValue: Self.stored(AutoResumePolicy.self, .autoResumePolicy, in: store) ?? .always)
        _controllerLayout = State(initialValue: Self.stored(TouchControlStyle.self, .controllerLayout, in: store) ?? .gameBoy)
        _soundMode = State(initialValue: Self.stored(SoundMode.self, .soundMode, in: store) ?? .followSilentSwitch)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Skip Boot Logo", isOn: $skipBootAnimation)
                } footer: {
                    Text("Library games open on the game instead of the boot logo. Quick Play always skips it.")
                }

                Section {
                    Picker("Controller Layout", selection: $controllerLayout) {
                        Text("Game Boy").tag(TouchControlStyle.gameBoy)
                        Text("Playtiles").tag(TouchControlStyle.playtiles)
                    }
                } footer: {
                    Text("Game Boy follows SameBoy’s layout. In Playtiles, tapping the game toggles Fast Forward.")
                }

                Section {
                    Picker("Sound", selection: $soundMode) {
                        Text("Follow Silent Switch").tag(SoundMode.followSilentSwitch)
                        Text("Always On").tag(SoundMode.alwaysOn)
                        Text("Always Off").tag(SoundMode.alwaysOff)
                    }
                } footer: {
                    Text("Always Off leaves music from other apps playing.")
                }

                Section {
                    Picker("Resume Games", selection: $autoResumePolicy) {
                        Text("Always").tag(AutoResumePolicy.always)
                        Text("Ask").tag(AutoResumePolicy.ask)
                        Text("Never").tag(AutoResumePolicy.never)
                    }
                } footer: {
                    Text("Whether a game picks up where you left off when you open it again or return to the app.")
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
            .onChange(of: skipBootAnimation) { _, newValue in save(newValue, .skipBootAnimation) }
            .onChange(of: autoResumePolicy) { _, newValue in save(newValue, .autoResumePolicy) }
            .onChange(of: controllerLayout) { _, newValue in save(newValue, .controllerLayout) }
            .onChange(of: soundMode) { _, newValue in save(newValue, .soundMode) }
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
