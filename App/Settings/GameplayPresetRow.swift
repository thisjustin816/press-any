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
    /// The models games here play on; more than one where each game gets its own, as under
    /// Automatic.
    let hardware: [PresetHardware]
    let store: any SettingsStore
    @ObservedObject var plus: PlusStore
    let refreshToken: Int
    let onChange: () -> Void

    @State private var preset: GameplayPreset = .standard
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            // A second Text is the option's subtitle.
            ForEach(GameplayPreset.builtIn, id: \.self) { choice in
                Button { choose(choice) } label: {
                    Text(choice.displayName)
                    Text(Self.detail(choice, plusUnlocked: plus.isUnlocked))
                }
            }
            // Custom isn't a choice, so its option says when it shows.
            Button {} label: {
                Text(plus.gate.label(GameplayPreset.custom.displayName, needsPlus: true))
                Text(Self.detail(.custom, plusUnlocked: true))
            }
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
                    Text(errorMessage ?? Self.detail(preset, plusUnlocked: plus.isUnlocked))
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
        .accessibilityValue("\(preset.displayName), \(errorMessage ?? Self.detail(preset, plusUnlocked: plus.isUnlocked))")
        .onAppear(perform: load)
        .onChange(of: refreshToken) { load() }
        .onChange(of: hardware) { load() }
    }

    /// Each preset's description, under the Preset row and under its option in the menu. A preset
    /// sets more than the screen, and the same words fit every model.
    static func detail(_ preset: GameplayPreset, plusUnlocked: Bool) -> String {
        switch preset {
        case .standard: "As you remember it, polished for today's screens"
        case .accurate: "As the original looked and felt"
        case .clean: "Just the game, with no effects added"
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
