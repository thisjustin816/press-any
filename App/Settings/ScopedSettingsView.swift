import EmulatorApplication
import EmulatorDomain
import Foundation
import GameplayInput
import SwiftUI

/// Settings overridden for one Game or Build. Each setting either inherits, showing the value it
/// gets and where that value comes from, or holds its own value until it is reset to inherit.
struct ScopedSettingsView: View {
    let title: String
    let scope: SettingsScope
    let system: GameSystem
    let gameID: UUID?
    let buildID: UUID?
    let store: any SettingsStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                InheritableSettingRow(
                    title: "Skip Boot Logo",
                    key: .skipBootAnimation,
                    defaultValue: false,
                    options: [(true, "On"), (false, "Off")],
                    context: context
                )
                InheritableSettingRow(
                    title: "Controller Layout",
                    key: .controllerLayout,
                    defaultValue: TouchControlStyle.gameBoy,
                    options: [(.gameBoy, "Game Boy"), (.playtiles, "Playtiles")],
                    context: context
                )
                InheritableSettingRow(
                    title: "Screen Scaling",
                    key: .screenScaling,
                    defaultValue: ScreenScaling.integer,
                    options: [(.integer, "Integer"), (.fill, "Fill")],
                    context: context
                )
                InheritableSettingRow(
                    title: "Resume Games",
                    key: .autoResumePolicy,
                    defaultValue: AutoResumePolicy.always,
                    options: [(.always, "Always"), (.ask, "Ask"), (.never, "Never")],
                    context: context
                )
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var context: InheritableSettingContext {
        InheritableSettingContext(scope: scope, system: system, gameID: gameID, buildID: buildID, store: store)
    }
}

struct InheritableSettingContext {
    let scope: SettingsScope
    let system: GameSystem
    let gameID: UUID?
    let buildID: UUID?
    let store: any SettingsStore

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

    var body: some View {
        Section {
            Picker(title, selection: $choice) {
                Text("Inherit (\(label(for: inheritedValue)))").tag(Choice.inherit)
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].1).tag(Choice.value(options[index].0))
                }
            }
        } footer: {
            Text(errorMessage ?? footer)
        }
        .onAppear(perform: load)
        .onChange(of: choice) { _, newValue in save(newValue) }
    }

    private var inheritedValue: Value {
        inherited.flatMap { try? $0.decode(Value.self) } ?? defaultValue
    }

    private var footer: String {
        switch choice {
        case .inherit:
            "Inherited from \(sourceName(inherited?.source))."
        case .value:
            "Set here. Choose Inherit to use \(label(for: inheritedValue)) from \(sourceName(inherited?.source)) again."
        }
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
        } catch {
            errorMessage = "Could not save the setting: \(error.localizedDescription)"
        }
    }
}
