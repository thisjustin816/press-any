import EmulatorApplication
import EmulatorDomain
import Foundation
import SwiftUI

/// The Gameplay preset for one scope. Every built-in preset is free; Custom is shown when the
/// settings under Customize match none of them.
struct GameplayPresetRow: View {
    let scope: SettingsScope
    let system: GameSystem
    let gameID: UUID?
    let buildID: UUID?
    let hardware: HardwareModel
    let store: any SettingsStore
    @ObservedObject var plus: PlusStore
    let refreshToken: Int
    let onChange: () -> Void

    @State private var preset: GameplayPreset = .standard
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            ForEach(GameplayPreset.builtIn, id: \.self) { choice in
                Button(choice.displayName) { choose(choice) }
            }
            Button(plus.gate.label(GameplayPreset.custom.displayName, needsPlus: true)) {}
                .disabled(true)
            Divider()
            Button("Reset to Inherited") { reset() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Preset").foregroundStyle(Color.primary)
                        if preset == .custom, !plus.isUnlocked { PlusBadge() }
                    }
                    Text(errorMessage ?? Self.detail(preset, hardware: hardware, plusUnlocked: plus.isUnlocked))
                        .font(.subheadline)
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                }
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    Text(plus.gate.label(preset.displayName, needsPlus: preset == .custom))
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                .foregroundStyle(Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Gameplay Preset")
        .accessibilityValue("\(preset.displayName), \(errorMessage ?? Self.detail(preset, hardware: hardware, plusUnlocked: plus.isUnlocked))")
        .onAppear(perform: load)
        .onChange(of: refreshToken) { load() }
        .onChange(of: hardware) { load() }
    }

    static func detail(_ preset: GameplayPreset, hardware: HardwareModel, plusUnlocked: Bool) -> String {
        switch preset {
        case .standard: "The screen as you remember it, cleaned up"
        case .accurate: "As on a \(hardware.displayName)"
        case .clean: "The game's pixels, with no screen effects"
        case .custom:
            plusUnlocked
                ? "Customize matches no preset"
                : "Kept from earlier settings. Changing them needs \(PlusProduct.name)."
        }
    }

    private func choose(_ newPreset: GameplayPreset) {
        do {
            try GameplayPresetSettings(store: store).apply(
                newPreset, at: scope, hardware: hardware, system: system, gameID: gameID, buildID: buildID
            )
            errorMessage = nil
            onChange()
            load()
        } catch {
            errorMessage = "Could not save the preset: \(error.localizedDescription)"
        }
    }

    private func reset() {
        do {
            try GameplayPresetSettings(store: store).reset(at: scope)
            errorMessage = nil
            onChange()
            load()
        } catch {
            errorMessage = "Could not reset the preset: \(error.localizedDescription)"
        }
    }

    private func load() {
        preset = GameplayPresetSettings(store: store).resolvedPreset(
            system: system, gameID: gameID, buildID: buildID, hardware: hardware
        )
    }
}
