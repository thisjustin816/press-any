import EmulatorApplication
import EmulatorDomain
import Foundation
import SwiftUI

/// App-wide settings. Values are stored at the app scope, so a System, Game or Build override
/// still wins for that launch.
struct AppSettingsView: View {
    private let store: any SettingsStore

    @State private var skipBootAnimation: Bool
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(store: any SettingsStore) {
        self.store = store
        _skipBootAnimation = State(initialValue: Self.storedBool(.skipBootAnimation, in: store) ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Skip Boot Logo", isOn: $skipBootAnimation)
                } footer: {
                    Text("Library games open on the game instead of the boot logo. Quick Play always skips it.")
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
            .onChange(of: skipBootAnimation) { _, newValue in
                do {
                    try store.set(newValue, key: SettingKey.skipBootAnimation.rawValue, scope: .app)
                    errorMessage = nil
                } catch {
                    errorMessage = "Could not save the setting: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func storedBool(_ key: SettingKey, in store: any SettingsStore) -> Bool? {
        guard let json = try? store.valueJSON(key: key.rawValue, scope: .app) else { return nil }
        return try? JSONDecoder().decode(Bool.self, from: Data(json.utf8))
    }
}
