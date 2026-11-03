import EmulatorApplication
import EmulatorDomain
import Foundation
import GameplayInput
import SwiftUI

/// Settings overridden for one system, Game or Build. Each setting either inherits, showing the
/// value it gets and where that value comes from, or holds its own value until it is reset to
/// inherit.
struct ScopedSettingsView: View {
    static let buttonBounceExplanation = "Button Bounce makes a button chatter briefly after each press and release, as the hardware's contacts do. Turn it off if a game counts one tap twice."
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
    /// A game whose header marks it for a Game Boy Color only, which the Model picker notes under
    /// Game Boy. Some such games still play on a Game Boy, so the note doesn't say they can't.
    var marksGameBoyColorOnly = false
    /// A Game Boy Camera cartridge, which shows the Game Boy Camera setting. System pages always
    /// show it, since they set it for every camera game.
    var hasCamera = false

    @Environment(\.dismiss) private var dismiss
    @State private var showsPlus = false
    /// The hardware games here run on, which decides the Screen Colors row and whether Game Boy
    /// Advance Colors shows. Read again after each change.
    @State private var hardware: HardwareModel?
    @State private var settingsRevision = 0
    @State private var presetError: String?

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
            gameplayPresetSection
            if let presetError { Section { Text(presetError).foregroundStyle(.red) } }
            displaySection
            controlsSection
            fastForwardSection
            playingSection
            if hasCamera || gameID == nil { cameraSection }
        }
        .scrollOverflowCue()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .plusSheet(isPresented: $showsPlus, store: plus)
        .onAppear(perform: refreshModel)
        .onChange(of: plus.isUnlocked) { refreshModel() }
    }

    private func refreshModel() {
        hardware = currentHardware()
    }

    private func settingsChanged() {
        let previous = hardware ?? currentHardware()
        let current = currentHardware()
        do {
            try GameplayPresetSettings(store: store).retargetBuiltInPreset(
                from: previous, to: current, at: scope, system: system, gameID: gameID, buildID: buildID
            )
            presetError = nil
        } catch {
            presetError = "Could not apply the preset to this Model: \(error.localizedDescription)"
        }
        hardware = current
        settingsRevision += 1
        onChange?()
    }

    /// Never Automatic: that resolves to the system's own hardware. Without Plus every game plays
    /// on Automatic.
    var resolvedHardware: HardwareModel {
        hardware ?? currentHardware()
    }

    private func currentHardware() -> HardwareModel {
        let stored = try? SettingsResolver(store: store).decode(
            HardwareModel.self,
            key: SettingKey.hardwareModel.rawValue,
            system: system,
            gameID: gameID,
            buildID: buildID
        )
        let model = plus.isUnlocked ? stored ?? .automatic : .automatic
        return model.resolved(for: system)
    }

    private var gameplayPresetSection: some View {
        Section {
            GameplayPresetRow(
                scope: scope,
                system: system,
                gameID: gameID,
                buildID: buildID,
                hardware: resolvedHardware,
                store: store,
                plus: plus,
                refreshToken: settingsRevision,
                onChange: {
                    settingsRevision += 1
                    onChange?()
                }
            )
            modelSetting
            screenColors
            NavigationLink {
                Form {
                    Section {
                        customGameplayRows
                    } footer: {
                        Text(Self.customizeFooter(plus.gate))
                    }
                }
                .scrollOverflowCue()
                .navigationTitle("Customize")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 6) {
                    Text("Customize")
                    if !plus.isUnlocked { PlusBadge() }
                }
            }
        } header: {
            Text("Gameplay")
        } footer: {
            Text(Self.gameplayFooter)
        }
    }

    static let gameplayFooter = "\(GameplayPreset.standardName) shows the screen as you remember it, cleaned up. Accurate imitates the Model's own screen or television, and Clean shows the game's pixels with no effects. Every preset and Screen Colors are free. Customize changes the settings a preset sets, one by one, with \(PlusProduct.name)."

    static func customizeFooter(_ gate: PlusGate) -> String {
        let rules = gate.isLocked(true)
            ? "Changing these needs \(PlusProduct.name). Choosing one opens the Plus screen and changes nothing."
            : "A change here makes the preset Custom, until every value matches a preset again."
        return rules + " Every display filter works on every Model. " + buttonBounceExplanation
    }

    private var modelSetting: some View {
        InheritableSettingRow(
            title: "Model",
            key: .hardwareModel,
            defaultValue: HardwareModel.automatic,
            options: HardwareModel.allCases.map { ($0, $0.displayName) },
            optionSubtitle: { $0 == .automatic ? HardwareModel.automaticSummary : nil },
            listSections: modelSections,
            explanation: plus.isUnlocked ? HardwareModel.settingExplanation : HardwareModel.lockedExplanation,
            needsPlus: \.needsPlus,
            reloadToken: settingsRevision,
            context: context
        )
    }

    /// What unset preset settings show and play with on this hardware.
    private var standard: GameplayPresetValues { GameplayPresetValues.standard(for: resolvedHardware) }

    @ViewBuilder private var customGameplayRows: some View {
        switch screenColorChoices {
        case .correction(let corrections):
            InheritableSettingRow(
                title: "Color Correction",
                key: .colorCorrection,
                defaultValue: standard.colorCorrection ?? ColorCorrection.defaultValue,
                options: corrections.map { ($0, $0.displayName) },
                listSections: [SettingOptionSection(title: "Color Correction", values: corrections)],
                explanation: ColorCorrection.explanation,
                reloadToken: settingsRevision,
                context: context
            )
        case .dmg, .superGameBoy:
            EmptyView()
        }
        if resolvedHardware.isGameBoyAdvance {
            InheritableSettingRow(
                title: "Game Boy Advance Colors",
                key: .advanceColors,
                defaultValue: standard.advanceColors ?? AdvanceColors.gameBoyAdvance,
                options: AdvanceColors.allCases.map { ($0, $0.displayName) },
                listSections: [SettingOptionSection(title: "Game Boy Advance Colors", values: AdvanceColors.allCases)],
                explanation: AdvanceColors.explanation,
                reloadToken: settingsRevision,
                context: context
            )
        }
        InheritableSettingRow(
            title: "Display Filter",
            key: .lcdFilter,
            defaultValue: standard.displayFilter,
            options: DisplayFilter.selectable.map { ($0, $0.displayName) },
            reloadToken: settingsRevision,
            context: context
        )
        InheritableSettingRow(
            title: "Frame Blending",
            key: .frameBlending,
            defaultValue: standard.frameBlending,
            options: FrameBlending.allCases.map { ($0, $0.displayName) },
            reloadToken: settingsRevision,
            context: context
        )
        InheritableSettingRow(
            title: "Button Bounce",
            key: .buttonBounce,
            defaultValue: standard.buttonBounce,
            options: [(true, "On"), (false, "Off")],
            reloadToken: settingsRevision,
            context: context
        )
    }

    private var displaySection: some View {
        Section {
            InheritableSettingRow(
                title: "Orientation",
                key: .orientation,
                defaultValue: ScreenOrientation.automatic,
                options: [(.automatic, "Automatic"), (.portrait, "Portrait"), (.landscape, "Landscape")],
                reloadToken: settingsRevision,
                context: context
            )
            InheritableSettingRow(
                title: "Screen Scaling",
                key: .screenScaling,
                defaultValue: ScreenScaling.integer,
                options: [(.integer, "Integer"), (.fill, "Fill")],
                reloadToken: settingsRevision,
                context: context
            )
        } header: {
            Text("Display")
        }
    }

    private var controlsSection: some View {
        Section {
            InheritableSettingRow(
                title: "Controller Layout",
                key: .controllerLayout,
                defaultValue: TouchControlStyle.gameBoy,
                options: [(.gameBoy, "Game Boy"), (.playtiles, "Playtiles")],
                isAvailable: ControllerLayoutAvailability.isAvailable,
                reloadToken: settingsRevision,
                context: context
            )
        } header: {
            Text("Controls")
        } footer: {
            if !ControllerLayoutAvailability.supportsPlaytiles {
                Text(ControllerLayoutAvailability.unavailableMessage)
            }
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
                reloadToken: settingsRevision,
                context: context
            )
            InheritableSettingRow(
                title: "Audio",
                key: .fastForwardAudio,
                defaultValue: FastForwardAudio.muted,
                options: FastForwardAudio.allCases.map { ($0, $0.displayName) },
                reloadToken: settingsRevision,
                context: context
            )
        }
    }

    private var playingSection: some View {
        Section {
            InheritableSettingRow(
                title: "Timed States",
                key: .timedStates,
                defaultValue: TimedStates.off,
                options: TimedStates.allCases.map { ($0, $0.displayName) },
                needsPlus: \.needsPlus,
                reloadToken: settingsRevision,
                context: context
            )
            InheritableSettingRow(
                title: "Resume Games",
                key: .autoResumePolicy,
                defaultValue: AutoResumePolicy.always,
                options: [(.always, "Always"), (.ask, "Ask"), (.never, "Never")],
                reloadToken: settingsRevision,
                context: context
            )
            InheritableSettingRow(
                title: "Skip Boot Logo",
                key: .skipBootAnimation,
                defaultValue: false,
                options: [(true, "On"), (false, "Off")],
                reloadToken: settingsRevision,
                context: context
            )
        } header: {
            Text("Playing")
        }
    }

    private var cameraSection: some View {
        Section("Game Boy Camera") {
            InheritableSettingRow(
                title: "Camera",
                key: .gameBoyCamera,
                defaultValue: GameBoyCamera.defaultValue,
                options: GameBoyCamera.allCases.map { ($0, $0.displayName) },
                listSections: [SettingOptionSection(title: "Camera", values: GameBoyCamera.allCases)],
                explanation: GameBoyCamera.explanation,
                reloadToken: settingsRevision,
                context: context
            )
        }
    }

    /// Automatic on its own, then each console's models.
    var modelSections: [SettingOptionSection<HardwareModel>] {
        [SettingOptionSection(values: [.automatic])] + HardwareConsole.allCases.map { console in
            SettingOptionSection(
                title: console.displayName,
                values: console.models,
                footer: console == .gameBoy && marksGameBoyColorOnly
                    ? "This game is made for a Game Boy Color. On these models it may play in black and white, or only show a message that it needs one."
                    : nil
            )
        }
    }

    var screenColorChoices: ScreenColorChoices { ScreenColorChoices(hardware: resolvedHardware) }

    /// A palette for hardware that shows one, free and outside the presets. Game Boy Color colors
    /// are Color Correction, under Customize.
    @ViewBuilder private var screenColors: some View {
        switch screenColorChoices {
        case .dmg(let palettes):
            InheritableSettingRow(
                title: "Screen Colors",
                key: .dmgPalette,
                defaultValue: DMGPalette.defaultValue,
                options: palettes.map { ($0, $0.displayName) },
                optionImage: { DMGPalettePreview.image(for: $0) },
                optionTitle: { $0.colorName },
                optionSubtitle: { "(\($0.originDescription))" },
                listSections: DMGPaletteGroup.allCases.map { group in
                    SettingOptionSection(title: group.rawValue, values: palettes.filter { group.contains($0) })
                },
                explanation: DMGPalette.explanation,
                normalizeValue: { $0.selectionValue },
                reloadToken: settingsRevision,
                context: context
            )
        case .correction:
            EmptyView()
        case .superGameBoy:
            LabeledContent {
                Text("Super Game Boy")
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Colors")
                    Text("Set by the game or the Super Game Boy")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var context: InheritableSettingContext {
        InheritableSettingContext(
            scope: scope,
            system: system,
            gameID: gameID,
            buildID: buildID,
            store: store,
            onChange: settingsChanged,
            plus: plus.gate,
            openPlus: { showsPlus = true }
        )
    }
}

/// The Screen Colors that apply on the hardware a game runs on.
enum ScreenColorChoices: Equatable {
    case dmg([DMGPalette])
    case correction([ColorCorrection])
    /// The game or the Super Game Boy sets the colors, so there is nothing to choose.
    case superGameBoy

    /// `hardware` is resolved, so Automatic doesn't arrive here.
    init(hardware: HardwareModel) {
        switch hardware {
        case .automatic, .gameBoy, .gameBoyPocket: self = .dmg(DMGPalette.selectableCases)
        case .superGameBoy, .superGameBoy2: self = .superGameBoy
        case .gameBoyColor, .gameBoyAdvance, .gameBoyPlayer: self = .correction(ColorCorrection.allCases)
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

struct SettingOptionSection<Value> {
    var title: String?
    let values: [Value]
    var footer: String?
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
    var optionImage: ((Value) -> Image)?
    var optionTitle: ((Value) -> String)?
    var optionSubtitle: ((Value) -> String?)?
    var listSections: [SettingOptionSection<Value>]?
    var explanation: String?
    var normalizeValue: (Value) -> Value = { $0 }
    /// Values that need Plus. Without it they're marked Plus, and choosing one opens the Plus screen.
    var needsPlus: (Value) -> Bool = { _ in false }
    var isAvailable: @MainActor (Value) -> Bool = { _ in true }
    var reloadToken = 0
    let context: InheritableSettingContext

    @State private var choice: Choice = .inherit
    @State private var inherited: ResolvedSetting?
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .body) private var checkmarkWidth: CGFloat = 20

    private var editNeedsPlus: Bool {
        GameplayPresetSettings.controlledKeys.contains(key)
    }

    var body: some View {
        Group {
            if let listSections {
                NavigationLink {
                    selectionList(sections: listSections)
                } label: {
                    rowLabel
                }
            } else {
                Menu {
                    Picker(title, selection: Binding(get: { choice }, set: { choose($0) })) {
                        Text(context.plus.label("\(inheritNote) (\(label(for: inheritedValue)))", needsPlus: editNeedsPlus))
                            .tag(Choice.inherit)
                        ForEach(options.indices, id: \.self) { index in
                            Text(context.plus.label(options[index].1, needsPlus: editNeedsPlus || needsPlus(options[index].0)))
                                .tag(Choice.value(options[index].0))
                                .disabled(!isAvailable(options[index].0))
                        }
                    }
                } label: {
                    rowLabel
                }
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue("\(label(for: effectiveValue)), \(errorMessage ?? note)")
        .onAppear(perform: load)
        .onChange(of: reloadToken) { load() }
    }

    private var rowLabel: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .foregroundStyle(Color.primary)
                    if context.plus.isLocked(editNeedsPlus)
                        || options.contains(where: { context.plus.isLocked(needsPlus($0.0)) }) {
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
                if listSections == nil {
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
            }
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: listSections == nil, vertical: true)
        }
        .contentShape(Rectangle())
    }

    private func selectionList(sections: [SettingOptionSection<Value>]) -> some View {
        Form {
            Section {
                selectionButton(
                    .inherit,
                    title: inheritNote,
                    subtitle: label(for: inheritedValue),
                    value: inheritedValue,
                    locked: context.plus.isLocked(editNeedsPlus)
                )
            }
            ForEach(sections.indices, id: \.self) { index in
                Section {
                    ForEach(sections[index].values, id: \.self) { value in
                        selectionButton(
                            .value(value),
                            title: optionTitle?(value) ?? label(for: value),
                            subtitle: optionSubtitle?(value),
                            value: value,
                            locked: context.plus.isLocked(editNeedsPlus || needsPlus(value))
                        )
                    }
                } header: {
                    if let title = sections[index].title {
                        Text(title)
                    }
                } footer: {
                    let notes = [sections[index].footer, index == sections.indices.last ? explanation : nil].compactMap { $0 }
                    if !notes.isEmpty {
                        Text(notes.joined(separator: "\n\n"))
                    }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .scrollOverflowCue()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A locked value is marked Plus, and choosing it opens the Plus screen.
    private func selectionButton(_ selection: Choice, title: String, subtitle: String?, value: Value,
                                 locked: Bool = false) -> some View {
        Button {
            choose(selection)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.primary)
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(Color.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if locked {
                    PlusBadge()
                }
                if let optionImage {
                    optionImage(value)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 48, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.3)))
                        .accessibilityHidden(true)
                }
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .opacity(choice == selection ? 1 : 0)
                    .frame(width: checkmarkWidth)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(choice == selection ? .isSelected : [])
        .disabled(selection != .inherit && !isAvailable(value))
    }

    private var inheritedValue: Value {
        normalizeValue(inherited.flatMap { try? $0.decode(Value.self) } ?? defaultValue)
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

    /// A preset setting changed by hand needs Plus; without it, choosing anything opens the Plus
    /// screen and saves nothing. A value that needs Plus does the same.
    private func choose(_ newChoice: Choice) {
        if context.plus.isLocked(editNeedsPlus) {
            context.openPlus()
            return
        }
        if case .value(let value) = newChoice, !isAvailable(value) { return }
        if case .value(let value) = newChoice, context.plus.isLocked(needsPlus(value)) {
            context.openPlus()
        } else {
            save(newChoice)
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
            choice = .value(normalizeValue(value))
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
            choice = newChoice
            errorMessage = nil
            context.onChange?()
        } catch {
            errorMessage = "Could not save the setting: \(error.localizedDescription)"
        }
    }
}
