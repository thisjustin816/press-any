import EmulatorApplication
import EmulatorDomain
import Foundation
import SwiftUI

/// App-wide settings. Values are stored at the app scope, so a System, Game or Build override
/// still wins for that launch.
struct AppSettingsView: View {
    private let store: any SettingsStore

    @State private var skipBootAnimation: Bool
    @State private var autoResumePolicy: AutoResumePolicy
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(store: any SettingsStore) {
        self.store = store
        _skipBootAnimation = State(initialValue: Self.stored(Bool.self, .skipBootAnimation, in: store) ?? false)
        _autoResumePolicy = State(initialValue: Self.stored(AutoResumePolicy.self, .autoResumePolicy, in: store) ?? .always)
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
