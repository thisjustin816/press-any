import EmulatorApplication
import EmulatorDomain
import Foundation
import SwiftUI

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

    @State private var preset: GameplayPreset = .custom
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button(GameplayPreset.clean.displayName) { choose(.clean) }
            Button(GameplayPreset.accurate.displayName) { choose(.accurate) }
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
                    Text(errorMessage ?? detail)
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
        .accessibilityValue("\(preset.displayName), \(errorMessage ?? detail)")
        .onAppear(perform: load)
        .onChange(of: refreshToken) { load() }
        .onChange(of: hardware) { load() }
    }

    private var detail: String {
        switch preset {
        case .clean: "No hardware or display effects"
        case .accurate: "Matched to \(hardware.displayName)"
        case .custom:
            plus.isUnlocked ? "Advanced settings differ from Clean or Accurate" : "Manual tuning requires \(PlusProduct.name)"
        }
    }

    private func choose(_ newPreset: GameplayPreset) {
        guard newPreset != .custom else { return }
        do {
            try GameplayPresetSettings(store: store).apply(newPreset, at: scope, hardware: hardware)
            preset = newPreset
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
        do {
            preset = try GameplayPresetSettings(store: store).resolvedPreset(
                system: system,
                gameID: gameID,
                buildID: buildID,
                hardware: hardware
            )
            errorMessage = nil
        } catch {
            preset = .custom
            errorMessage = "Could not read the preset: \(error.localizedDescription)"
        }
    }
}
