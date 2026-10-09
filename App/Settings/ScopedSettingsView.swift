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
    /// Plus options stay listed without it, and choosing one opens the Plus screen.
    @ObservedObject var plus: PlusStore
    /// Called after each saved change, so an open game can apply it.
    var onChange: (() -> Void)?
    /// False when App Settings pushes it as a page, which has its own navigation and Done.
    var inSheet = true

    @Environment(\.dismiss) private var dismiss
    @State private var showsPlus = false

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
        .plusSheet(isPresented: $showsPlus, store: plus)
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
                needsPlus: \.needsPlus,
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
                title: "Timed States",
                key: .timedStates,
                defaultValue: TimedStates.off,
                options: TimedStates.allCases.map { ($0, $0.displayName) },
                needsPlus: \.needsPlus,
                context: context
            )
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

    var screenColorChoices: ScreenColorChoices { ScreenColorChoices(system: system) }

    /// Each system has its own Screen Colors, so only the one that applies shows.
    @ViewBuilder private var screenColors: some View {
        switch screenColorChoices {
        case .dmg(let palettes):
            InheritableSettingRow(
                title: "Screen Colors",
                key: .dmgPalette,
                defaultValue: DMGPalette.defaultValue,
                options: palettes.map { ($0, $0.displayName) },
                context: context
            )
        case .correction(let corrections):
            InheritableSettingRow(
                title: "Screen Colors",
                key: .colorCorrection,
                defaultValue: ColorCorrection.defaultValue,
                options: corrections.map { ($0, $0.displayName) },
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
            onChange: onChange,
            plus: plus.gate,
            openPlus: { showsPlus = true }
        )
    }
}

enum ScreenColorChoices {
    case dmg([DMGPalette])
    case correction([ColorCorrection])

    init(system: GameSystem) {
        switch system {
        case .gameBoy: self = .dmg(DMGPalette.allCases)
        case .gameBoyColor: self = .correction(ColorCorrection.allCases)
        }
    }
}

struct InheritableSettingContext {
    let scope: SettingsScope
    let system: GameSystem
    let gameID: UUID?
    let buildID: UUID?
    let store: any SettingsStore
    var onChange: (() -> Void)?
    var plus = PlusGate(isUnlocked: true)
    var openPlus: () -> Void = {}

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
    /// Values that need Plus. Without it they're marked Plus, and choosing one opens the Plus screen.
    var needsPlus: (Value) -> Bool = { _ in false }
    let context: InheritableSettingContext

    @State private var choice: Choice = .inherit
    @State private var inherited: ResolvedSetting?
    @State private var errorMessage: String?

    /// The value in effect stays on the right whatever the note says. A menu-style Picker moves its
    /// value under the title once the title and note need the width, so the row is the label of a
    /// menu that holds the Picker, and a tap anywhere on it opens the menu as before.
    var body: some View {
        Menu {
            Picker(title, selection: Binding(get: { choice }, set: { choose($0) })) {
                Text("\(inheritNote) (\(label(for: inheritedValue)))").tag(Choice.inherit)
                ForEach(options.indices, id: \.self) { index in
                    Text(context.plus.label(options[index].1, needsPlus: needsPlus(options[index].0)))
                        .tag(Choice.value(options[index].0))
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .foregroundStyle(Color.primary)
                        if options.contains(where: { context.plus.isLocked(needsPlus($0.0)) }) {
                            PlusBadge()
                        }
                    }
                    Text(errorMessage ?? note)
                        .font(.subheadline)
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    Text(context.plus.label(label(for: effectiveValue), needsPlus: needsPlus(effectiveValue)))
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
    /// beside the same words. A Plus value without Plus is kept, and says what plays instead.
    private var note: String {
        let source = switch choice {
        case .inherit: inheritNote
        case .value: "Set here"
        }
        return context.plus.isLocked(needsPlus(effectiveValue)) ? "\(source). \(label(for: defaultValue)) without Plus" : source
    }

    /// A Plus value without Plus opens the Plus screen and leaves the choice as it was.
    private func choose(_ newChoice: Choice) {
        if case .value(let value) = newChoice, context.plus.isLocked(needsPlus(value)) {
            context.openPlus()
        } else {
            choice = newChoice
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
