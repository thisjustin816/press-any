import EmulatorApplication
import EmulatorDomain
import Foundation
import GameplayInput
import SwiftUI

/// Settings overridden for one system, Game or Build. Each setting either inherits, showing the
/// value it gets and where that value comes from, or holds its own value until it is reset to
/// inherit.
struct ScopedSettingsView: View {
    let title: String
    let scope: SettingsScope
    let system: GameSystem
    let gameID: UUID?
    let buildID: UUID?
    let store: any SettingsStore
    /// Called after each saved change, so an open game can apply it.
    var onChange: (() -> Void)?
    /// False when App Settings pushes it as a page, which has its own navigation and Done.
    var inSheet = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if inSheet {
            NavigationStack {
                form.toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            displaySection
            controlsSection
            fastForwardSection
            playingSection
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // Separate properties keep each section small enough for the compiler to type-check quickly.
    private var displaySection: some View {
        Section {
            InheritableSettingRow(
                title: "Orientation",
                key: .orientation,
                defaultValue: ScreenOrientation.automatic,
                options: [(.automatic, "Automatic"), (.portrait, "Portrait"), (.landscape, "Landscape")],
                context: context
            )
            InheritableSettingRow(
                title: "Screen Scaling",
                key: .screenScaling,
                defaultValue: ScreenScaling.integer,
                options: [(.integer, "Integer"), (.fill, "Fill")],
                context: context
            )
            screenColors
            InheritableSettingRow(
                title: "LCD Filter",
                key: .lcdFilter,
                defaultValue: LCDFilter.off,
                options: LCDFilter.allCases.map { ($0, $0.displayName) },
                context: context
            )
            InheritableSettingRow(
                title: "Frame Blending",
                key: .frameBlending,
                defaultValue: FrameBlending.off,
                options: FrameBlending.allCases.map { ($0, $0.displayName) },
                context: context
            )
        } header: {
            Text("Display")
        } footer: {
            Text(system == .gameBoy ? DMGPalette.explanation : ColorCorrection.explanation)
        }
    }

    private var controlsSection: some View {
        Section("Controls") {
            InheritableSettingRow(
                title: "Controller Layout",
                key: .controllerLayout,
                defaultValue: TouchControlStyle.gameBoy,
                options: [(.gameBoy, "Game Boy"), (.playtiles, "Playtiles")],
                context: context
            )
        }
    }

    /// Named as on App Settings' Playing page: Speed and Audio under Fast Forward.
    private var fastForwardSection: some View {
        Section("Fast Forward") {
            InheritableSettingRow(
                title: "Speed",
                key: .fastForwardSpeed,
                defaultValue: FastForwardSpeed.x2,
                options: FastForwardSpeed.allCases.map { ($0, $0.displayName) },
                context: context
            )
            InheritableSettingRow(
                title: "Audio",
                key: .fastForwardAudio,
                defaultValue: FastForwardAudio.muted,
                options: FastForwardAudio.allCases.map { ($0, $0.displayName) },
                context: context
            )
        }
    }

    private var playingSection: some View {
        Section("Playing") {
            InheritableSettingRow(
                title: "Resume Games",
                key: .autoResumePolicy,
                defaultValue: AutoResumePolicy.always,
                options: [(.always, "Always"), (.ask, "Ask"), (.never, "Never")],
                context: context
            )
            InheritableSettingRow(
                title: "Skip Boot Logo",
                key: .skipBootAnimation,
                defaultValue: false,
                options: [(true, "On"), (false, "Off")],
                context: context
            )
        }
    }

    /// Each system has its own Screen Colors, so only the one that applies shows.
    @ViewBuilder private var screenColors: some View {
        switch system {
        case .gameBoy:
            InheritableSettingRow(
                title: "Screen Colors",
                key: .dmgPalette,
                defaultValue: DMGPalette.defaultValue,
                options: DMGPalette.allCases.map { ($0, $0.displayName) },
                context: context
            )
        case .gameBoyColor:
            InheritableSettingRow(
                title: "Screen Colors",
                key: .colorCorrection,
                defaultValue: ColorCorrection.defaultValue,
                options: ColorCorrection.allCases.map { ($0, $0.displayName) },
                context: context
            )
        }
    }

    private var context: InheritableSettingContext {
        InheritableSettingContext(
            scope: scope,
            system: system,
            gameID: gameID,
            buildID: buildID,
            store: store,
            onChange: onChange
        )
    }
}

struct InheritableSettingContext {
    let scope: SettingsScope
    let system: GameSystem
    let gameID: UUID?
    let buildID: UUID?
    let store: any SettingsStore
    var onChange: (() -> Void)?

    func edit(_ key: SettingKey) -> ScopedSetting? {
        try? SettingsResolver(store: store).edit(
            key: key.rawValue,
            at: scope,
            system: system,
            gameID: gameID,
            buildID: buildID
        )
    }
}

private struct InheritableSettingRow<Value: Codable & Hashable>: View {
    private enum Choice: Hashable {
        case inherit
        case value(Value)
    }

    let title: String
    let key: SettingKey
    let defaultValue: Value
    let options: [(Value, String)]
    let context: InheritableSettingContext

    @State private var choice: Choice = .inherit
    @State private var inherited: ResolvedSetting?
    @State private var errorMessage: String?

    /// The value in effect stays on the right whatever the note says. A menu-style Picker moves its
    /// value under the title once the title and note need the width, so the row is the label of a
    /// menu that holds the Picker, and a tap anywhere on it opens the menu as before.
    var body: some View {
        Menu {
            Picker(title, selection: $choice) {
                Text("\(inheritNote) (\(label(for: inheritedValue)))").tag(Choice.inherit)
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].1).tag(Choice.value(options[index].0))
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.primary)
                    Text(errorMessage ?? note)
                        .font(.subheadline)
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    Text(label(for: effectiveValue))
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .foregroundStyle(Color.secondary)
                .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue("\(label(for: effectiveValue)), \(errorMessage ?? note)")
        .onAppear(perform: load)
        .onChange(of: choice) { _, newValue in save(newValue) }
    }

    private var inheritedValue: Value {
        inherited.flatMap { try? $0.decode(Value.self) } ?? defaultValue
    }

    private var effectiveValue: Value {
        switch choice {
        case .inherit: inheritedValue
        case .value(let value): value
        }
    }

    /// Where the value comes from, under the setting's title. What it overrides shows in the menu,
    /// beside the same words.
    private var note: String {
        switch choice {
        case .inherit: inheritNote
        case .value: "Set here"
        }
    }

    /// "Default" when no level above sets the value, since there is nothing to inherit then;
    /// otherwise the level it comes from.
    private var inheritNote: String {
        (inherited?.source).map { "From \(sourceName($0))" } ?? "Default"
    }

    private func label(for value: Value) -> String {
        options.first { $0.0 == value }?.1 ?? String(describing: value)
    }

    private func sourceName(_ source: SettingsScope?) -> String {
        switch source {
        case nil: "the default"
        case .app: "App Settings"
        case .system(.gameBoyColor): "Game Boy Color settings"
        case .system: "Game Boy settings"
        case .game: "this Game"
        case .build: "this Build"
        }
    }

    private func load() {
        guard let setting = context.edit(key) else { return }
        inherited = setting.inherited
        if let json = setting.overrideJSON, let value = try? JSONDecoder().decode(Value.self, from: Data(json.utf8)) {
            choice = .value(value)
        } else {
            choice = .inherit
        }
    }

    private func save(_ newChoice: Choice) {
        do {
            switch newChoice {
            case .inherit:
                try context.store.removeValue(key: key.rawValue, scope: context.scope)
            case .value(let value):
                try context.store.set(value, key: key.rawValue, scope: context.scope)
            }
            errorMessage = nil
            context.onChange?()
        } catch {
            errorMessage = "Could not save the setting: \(error.localizedDescription)"
        }
    }
}
