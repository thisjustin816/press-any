from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"missing replacement in {path}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))


settings = Path("Packages/EmulatorKit/Sources/EmulatorDomain/Settings.swift")
text = settings.read_text()
old_enum = '''/// Built-in display effects. Raw values are stored in settings.
public enum LCDFilter: String, Codable, Sendable, CaseIterable {
    case off
    case lcd1x
    case lcd3x

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .lcd1x: "LCD 1×"
        case .lcd3x: "LCD 3×"
        }
    }
}

'''
if old_enum not in text:
    raise SystemExit("LCDFilter enum block changed")
text = text.replace(old_enum, "", 1)
text = text.replace(
    "/// `LCDFilter`, unset means `.off`. Independent of the picture’s scaling.",
    "/// `DisplayFilter`, unset means `.off`. The stored key keeps its v1.0 name for compatibility.",
)
settings.write_text(text)

Path("Packages/EmulatorKit/Sources/EmulatorDomain/GameplayPreset.swift").write_text(r'''/// Built-in picture treatments. Raw values are stored under the existing `lcdFilter` setting key,
/// whose name is kept for compatibility with v1.0 settings and backups.
public enum DisplayFilter: String, Codable, Sendable, CaseIterable {
    case off
    case lcd1x
    case lcd3x
    case crt240p
    case gameCubeTV

    public static let handheldCases: [Self] = [.off, .lcd1x, .lcd3x]

    /// Filters that make sense for the resolved hardware model. The older LCD effects stay
    /// available on television-output models so saved custom setups remain editable.
    public static func selectable(for hardware: HardwareModel) -> [Self] {
        switch hardware {
        case .superGameBoy, .superGameBoy2: [.off, .crt240p, .lcd1x, .lcd3x]
        case .gameBoyPlayer: [.off, .gameCubeTV, .lcd1x, .lcd3x]
        case .automatic, .gameBoy, .gameBoyPocket, .gameBoyColor, .gameBoyAdvance: handheldCases
        }
    }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .lcd1x: "LCD 1×"
        case .lcd3x: "LCD 3×"
        case .crt240p: "CRT 240p"
        case .gameCubeTV: "GameCube TV"
        }
    }
}

/// A high-level gameplay presentation. Custom is derived when the controlled low-level settings
/// do not exactly match either built-in preset; it is never stored independently.
public enum GameplayPreset: String, Codable, Sendable, CaseIterable {
    case raw
    case accurate
    case custom

    public var displayName: String {
        switch self {
        case .raw: "Raw"
        case .accurate: "Accurate"
        case .custom: "Custom"
        }
    }
}

/// The low-level settings a built-in gameplay preset controls for one resolved hardware model.
public struct GameplayPresetValues: Equatable, Sendable {
    public let displayFilter: DisplayFilter
    public let frameBlending: FrameBlending
    public let buttonBounce: Bool
    public let colorCorrection: ColorCorrection?
    public let dmgPalette: DMGPalette?
    public let advanceColors: AdvanceColors?

    public init(
        displayFilter: DisplayFilter,
        frameBlending: FrameBlending,
        buttonBounce: Bool,
        colorCorrection: ColorCorrection? = nil,
        dmgPalette: DMGPalette? = nil,
        advanceColors: AdvanceColors? = nil
    ) {
        self.displayFilter = displayFilter
        self.frameBlending = frameBlending
        self.buttonBounce = buttonBounce
        self.colorCorrection = colorCorrection
        self.dmgPalette = dmgPalette
        self.advanceColors = advanceColors
    }

    /// `hardware` is expected to be resolved rather than Automatic. Automatic is treated as the
    /// original Game Boy only as a defensive fallback.
    public static func values(for preset: GameplayPreset, hardware: HardwareModel) -> Self? {
        switch preset {
        case .custom:
            return nil
        case .raw:
            switch hardware {
            case .automatic, .gameBoy, .gameBoyPocket:
                return Self(displayFilter: .off, frameBlending: .off, buttonBounce: false, dmgPalette: .cgbLeftB)
            case .superGameBoy, .superGameBoy2:
                return Self(displayFilter: .off, frameBlending: .off, buttonBounce: false)
            case .gameBoyColor:
                return Self(displayFilter: .off, frameBlending: .off, buttonBounce: false, colorCorrection: .off)
            case .gameBoyAdvance, .gameBoyPlayer:
                return Self(
                    displayFilter: .off,
                    frameBlending: .off,
                    buttonBounce: false,
                    colorCorrection: .off,
                    advanceColors: .gameBoyColor
                )
            }
        case .accurate:
            switch hardware {
            case .automatic, .gameBoy:
                return Self(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, dmgPalette: .dmgGreen)
            case .gameBoyPocket:
                return Self(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, dmgPalette: .pocket)
            case .superGameBoy, .superGameBoy2:
                return Self(displayFilter: .crt240p, frameBlending: .off, buttonBounce: false)
            case .gameBoyColor:
                return Self(displayFilter: .lcd3x, frameBlending: .blend, buttonBounce: true, colorCorrection: .accurate)
            case .gameBoyAdvance:
                return Self(
                    displayFilter: .lcd3x,
                    frameBlending: .blend,
                    buttonBounce: true,
                    colorCorrection: .accurate,
                    advanceColors: .gameBoyAdvance
                )
            case .gameBoyPlayer:
                return Self(
                    displayFilter: .gameCubeTV,
                    frameBlending: .off,
                    buttonBounce: false,
                    colorCorrection: .off,
                    advanceColors: .gameBoyColor
                )
            }
        }
    }
}
''')

Path("Packages/EmulatorKit/Sources/EmulatorApplication/UseCases/GameplayPresetSettings.swift").write_text(r'''import EmulatorDomain
import Foundation

/// Applies and recognizes gameplay presets without adding a persisted preset setting. The existing
/// low-level settings remain the source of truth, so old installs keep their exact behavior.
public struct GameplayPresetSettings: Sendable {
    private let store: any SettingsStore
    private let resolver: SettingsResolver

    public init(store: any SettingsStore) {
        self.store = store
        self.resolver = SettingsResolver(store: store)
    }

    public func resolvedPreset(
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil,
        hardware: HardwareModel
    ) throws -> GameplayPreset {
        if let raw = GameplayPresetValues.values(for: .raw, hardware: hardware),
           try matches(raw, system: system, gameID: gameID, buildID: buildID) {
            return .raw
        }
        if let accurate = GameplayPresetValues.values(for: .accurate, hardware: hardware),
           try matches(accurate, system: system, gameID: gameID, buildID: buildID) {
            return .accurate
        }
        return .custom
    }

    /// Writes the built-in preset at exactly this scope. Custom is a derived state and cannot be
    /// applied directly; edit any controlled advanced setting to make a preset Custom.
    public func apply(_ preset: GameplayPreset, at scope: SettingsScope, hardware: HardwareModel) throws {
        guard let values = GameplayPresetValues.values(for: preset, hardware: hardware) else { return }
        try store.set(values.displayFilter, key: SettingKey.lcdFilter.rawValue, scope: scope)
        try store.set(values.frameBlending, key: SettingKey.frameBlending.rawValue, scope: scope)
        try store.set(values.buttonBounce, key: SettingKey.buttonBounce.rawValue, scope: scope)
        if let value = values.colorCorrection {
            try store.set(value, key: SettingKey.colorCorrection.rawValue, scope: scope)
        }
        if let value = values.dmgPalette {
            try store.set(value, key: SettingKey.dmgPalette.rawValue, scope: scope)
        }
        if let value = values.advanceColors {
            try store.set(value, key: SettingKey.advanceColors.rawValue, scope: scope)
        }
    }

    /// Removes every setting the presets control at this scope, revealing the inherited values.
    public func reset(at scope: SettingsScope) throws {
        for key in Self.controlledKeys {
            try store.removeValue(key: key.rawValue, scope: scope)
        }
    }

    private func matches(
        _ expected: GameplayPresetValues,
        system: GameSystem,
        gameID: UUID?,
        buildID: UUID?
    ) throws -> Bool {
        let filter = try resolver.decode(
            DisplayFilter.self, key: SettingKey.lcdFilter.rawValue,
            system: system, gameID: gameID, buildID: buildID
        ) ?? .off
        guard filter == expected.displayFilter else { return false }

        let blending = try resolver.decode(
            FrameBlending.self, key: SettingKey.frameBlending.rawValue,
            system: system, gameID: gameID, buildID: buildID
        ) ?? .off
        guard blending == expected.frameBlending else { return false }

        let bounce = try resolver.decode(
            Bool.self, key: SettingKey.buttonBounce.rawValue,
            system: system, gameID: gameID, buildID: buildID
        ) ?? true
        guard bounce == expected.buttonBounce else { return false }

        if let expectedValue = expected.colorCorrection {
            let value = try resolver.decode(
                ColorCorrection.self, key: SettingKey.colorCorrection.rawValue,
                system: system, gameID: gameID, buildID: buildID
            ) ?? .defaultValue
            guard value == expectedValue else { return false }
        }
        if let expectedValue = expected.dmgPalette {
            let value = try resolver.decode(
                DMGPalette.self, key: SettingKey.dmgPalette.rawValue,
                system: system, gameID: gameID, buildID: buildID
            ) ?? .defaultValue
            guard value == expectedValue else { return false }
        }
        if let expectedValue = expected.advanceColors {
            let value = try resolver.decode(
                AdvanceColors.self, key: SettingKey.advanceColors.rawValue,
                system: system, gameID: gameID, buildID: buildID
            ) ?? .gameBoyAdvance
            guard value == expectedValue else { return false }
        }
        return true
    }

    private static let controlledKeys: [SettingKey] = [
        .lcdFilter, .frameBlending, .buttonBounce, .colorCorrection, .dmgPalette, .advanceColors,
    ]
}
''')

Path("Packages/EmulatorKit/Tests/EmulatorApplicationTests/GameplayPresetSettingsTests.swift").write_text(r'''import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class GameplayPresetSettingsTests: XCTestCase {
    func testAccurateValuesAreSpecificToTheHardware() throws {
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .gameBoy),
            GameplayPresetValues(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, dmgPalette: .dmgGreen)
        )
        XCTAssertEqual(GameplayPresetValues.values(for: .accurate, hardware: .gameBoyPocket)?.dmgPalette, .pocket)
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .gameBoyColor),
            GameplayPresetValues(
                displayFilter: .lcd3x, frameBlending: .blend, buttonBounce: true, colorCorrection: .accurate
            )
        )
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .superGameBoy2),
            GameplayPresetValues(displayFilter: .crt240p, frameBlending: .off, buttonBounce: false)
        )
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .gameBoyPlayer),
            GameplayPresetValues(
                displayFilter: .gameCubeTV,
                frameBlending: .off,
                buttonBounce: false,
                colorCorrection: .off,
                advanceColors: .gameBoyColor
            )
        )
    }

    func testApplyingPresetAndManualChangeDeriveAccurateCustomAndAccurateAgain() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        let scope = SettingsScope.system(.gameBoyColor)

        try presets.apply(.accurate, at: scope, hardware: .gameBoyColor)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .accurate)

        try store.set(FrameBlending.off, key: SettingKey.frameBlending.rawValue, scope: scope)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .custom)

        try store.set(FrameBlending.blend, key: SettingKey.frameBlending.rawValue, scope: scope)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .accurate)
    }

    func testPresetOverridesAndResetPreserveTheExistingInheritanceModel() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        let gameID = UUID(), buildID = UUID()

        try presets.apply(.raw, at: .app, hardware: .gameBoyColor)
        XCTAssertEqual(
            try presets.resolvedPreset(system: .gameBoyColor, gameID: gameID, buildID: buildID, hardware: .gameBoyColor),
            .raw
        )

        try presets.apply(.accurate, at: .game(gameID), hardware: .gameBoyColor)
        XCTAssertEqual(
            try presets.resolvedPreset(system: .gameBoyColor, gameID: gameID, buildID: buildID, hardware: .gameBoyColor),
            .accurate
        )

        try presets.reset(at: .game(gameID))
        XCTAssertEqual(
            try presets.resolvedPreset(system: .gameBoyColor, gameID: gameID, buildID: buildID, hardware: .gameBoyColor),
            .raw
        )
    }

    func testExistingDefaultsRemainCustomInsteadOfChangingBehaviorDuringMigration() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoy, hardware: .gameBoy), .custom)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .custom)
    }

    func testRawRemovesDisplayAndInputAuthenticityEffects() throws {
        let gbc = try XCTUnwrap(GameplayPresetValues.values(for: .raw, hardware: .gameBoyColor))
        XCTAssertEqual(gbc.displayFilter, .off)
        XCTAssertEqual(gbc.colorCorrection, .off)
        XCTAssertEqual(gbc.frameBlending, .off)
        XCTAssertFalse(gbc.buttonBounce)

        let gbp = try XCTUnwrap(GameplayPresetValues.values(for: .raw, hardware: .gameBoyPlayer))
        XCTAssertEqual(gbp.displayFilter, .off)
        XCTAssertEqual(gbp.advanceColors, .gameBoyColor)
        XCTAssertFalse(gbp.buttonBounce)
    }
}
''')

# Runtime and tests now decode the same persisted raw strings with the broader type. The setting key
# itself stays `lcdFilter` and is not migrated.
for root in [Path("App"), Path("AppTests"), Path("Packages/EmulatorKit")]:
    for path in root.rglob("*.swift"):
        if path == settings or path.name == "GameplayPreset.swift":
            continue
        source = path.read_text()
        updated = re.sub(r"\bLCDFilter\b", "DisplayFilter", source)
        if updated != source:
            path.write_text(updated)

renderer = Path("App/Gameplay/MetalRenderer.swift")
source = renderer.read_text()
replace = "        case .lcd3x: 3\n        }"
if replace not in source:
    raise SystemExit("MetalRenderer shader mode anchor changed")
source = source.replace(replace, "        case .lcd3x: 3\n        case .crt240p: 4\n        case .gameCubeTV: 5\n        }", 1)
renderer.write_text(source)

shader = Path("App/Gameplay/Shaders.metal")
source = shader.read_text()
anchor = '''float4 blendedSample(texture2d<float> newest, texture2d<float> previous, texture2d<float> older,
                     sampler s, float2 coord, constant float4 &weights) {
    float4 color = newest.sample(s, coord) * weights.x;
    if (weights.y > 0) color += previous.sample(s, coord) * weights.y;
    if (weights.z > 0) color += older.sample(s, coord) * weights.z;
    return color;
}
'''
if anchor not in source:
    raise SystemExit("blendedSample anchor changed")
tv = anchor + r'''

// Television-output presets are deliberately restrained. CRT 240p models a consumer TV with
// visible beam structure and mild horizontal bleed; GameCube TV stays cleaner because Game Boy
// Player could be used through either interlaced or progressive GameCube output.
float4 tvColor(texture2d<float> newest, texture2d<float> previous, texture2d<float> older,
               sampler s, float2 coord, float2 texel, float2 size,
               constant float4 &weights, uint mode) {
    float2 dx = float2(0.55 / max(size.x, 1.0), 0.0);
    float4 center = blendedSample(newest, previous, older, s, coord, weights);
    float4 neighbors = 0.5 * (
        blendedSample(newest, previous, older, s, coord - dx, weights) +
        blendedSample(newest, previous, older, s, coord + dx, weights)
    );
    float softness = mode == 4 ? 0.28 : 0.12;
    float4 color = mix(center, neighbors, softness);

    float cellY = fract(texel.y);
    float beam = smoothstep(0.0, 0.35, cellY) * (1.0 - smoothstep(0.65, 1.0, cellY));
    float beamAmount = mode == 4 ? 0.20 : 0.055;
    float luminance = 1.0 - beamAmount * (1.0 - beam);
    if (mode == 4) {
        luminance *= 0.975 + 0.025 * cos((texel.x + 0.5) * 6.2831853);
    }
    return float4(color.rgb * luminance, color.a);
}
'''
source = source.replace(anchor, tv, 1)
old_nearest = '''    float4 color = blendedSample(newest, previous, older, s, in.texCoord, blendWeights);
    return lcdColor(color, in.texCoord * size, lcdMode);'''
new_nearest = '''    float2 texel = in.texCoord * size;
    if (lcdMode == 4 || lcdMode == 5) {
        return tvColor(newest, previous, older, s, in.texCoord, texel, size, blendWeights, lcdMode);
    }
    float4 color = blendedSample(newest, previous, older, s, in.texCoord, blendWeights);
    return lcdColor(color, texel, lcdMode);'''
if old_nearest not in source:
    raise SystemExit("nearest fragment anchor changed")
source = source.replace(old_nearest, new_nearest, 1)
old_sharp = '''    float4 color = blendedSample(newest, previous, older, s, texel / size, blendWeights);
    return lcdColor(color, in.texCoord * size, lcdMode);'''
new_sharp = '''    float2 sampleCoord = texel / size;
    float2 displayTexel = in.texCoord * size;
    if (lcdMode == 4 || lcdMode == 5) {
        return tvColor(newest, previous, older, s, sampleCoord, displayTexel, size, blendWeights, lcdMode);
    }
    float4 color = blendedSample(newest, previous, older, s, sampleCoord, blendWeights);
    return lcdColor(color, displayTexel, lcdMode);'''
if old_sharp not in source:
    raise SystemExit("sharp fragment anchor changed")
source = source.replace(old_sharp, new_sharp, 1)
shader.write_text(source)

pages = Path("App/Settings/AppSettingsPages.swift")
source = pages.read_text()
source = source.replace(r"ForEach(DisplayFilter.allCases, id: \.self)", r"ForEach(DisplayFilter.handheldCases, id: \.self)")
source = source.replace('Text("LCD Filter")', 'Text("Display Filter")')
source = source.replace("LCD filters come with \\(PlusProduct.name).", "Display filters come with \\(PlusProduct.name).")
pages.write_text(source)

scoped = Path("App/Settings/ScopedSettingsView.swift")
source = scoped.read_text()
replace_once(
    scoped,
    "    @State private var hardware: HardwareModel?\n",
    "    @State private var hardware: HardwareModel?\n    @State private var settingsRevision = 0\n",
)
source = scoped.read_text()
replace_once(scoped, "        Form {\n            displaySection", "        Form {\n            gameplayPresetSection\n            displaySection")
source = scoped.read_text()
marker = "    // Separate properties keep each section small enough for the compiler to type-check quickly.\n    private var displaySection: some View {"
preset_section = r'''    private var gameplayPresetSection: some View {
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
        } header: {
            Text("Gameplay")
        } footer: {
            Text("Raw removes display and input authenticity effects. Accurate uses a curated setup for the selected Model. Changing any controlled setting below makes the result Custom.")
        }
    }

    // Separate properties keep each section small enough for the compiler to type-check quickly.
    private var displaySection: some View {'''
replace_once(scoped, marker, preset_section)
source = scoped.read_text()
source = source.replace('title: "LCD Filter"', 'title: "Display Filter"')
source = source.replace(
    "options: DisplayFilter.allCases.map { ($0, $0.displayName) }",
    "options: DisplayFilter.selectable(for: resolvedHardware).map { ($0, $0.displayName) }",
)
old_context = '''            onChange: {
                onChange?()
                refreshModel()
            },'''
new_context = '''            onChange: {
                settingsRevision += 1
                onChange?()
                refreshModel()
            },'''
if old_context not in source:
    raise SystemExit("ScopedSettingsView context anchor changed")
source = source.replace(old_context, new_context, 1)
source = re.sub(r"(?m)^(\s*)context: context$", r"\1reloadToken: settingsRevision,\n\1context: context", source)
old_row = "    var isAvailable: @MainActor (Value) -> Bool = { _ in true }\n    let context: InheritableSettingContext"
new_row = "    var isAvailable: @MainActor (Value) -> Bool = { _ in true }\n    var reloadToken = 0\n    let context: InheritableSettingContext"
if old_row not in source:
    raise SystemExit("InheritableSettingRow property anchor changed")
source = source.replace(old_row, new_row, 1)
old_appear = "        .onAppear(perform: load)\n"
if old_appear not in source:
    raise SystemExit("InheritableSettingRow onAppear anchor changed")
source = source.replace(old_appear, old_appear + "        .onChange(of: reloadToken) { load() }\n", 1)
scoped.write_text(source)

Path("App/Settings/GameplayPresetRow.swift").write_text(r'''import EmulatorApplication
import EmulatorDomain
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
    @State private var showsPlus = false

    var body: some View {
        Menu {
            Button(GameplayPreset.raw.displayName) { choose(.raw) }
            Button(plus.gate.label(GameplayPreset.accurate.displayName, needsPlus: accurateNeedsPlus)) {
                choose(.accurate)
            }
            Button(GameplayPreset.custom.displayName) {}
                .disabled(true)
            Divider()
            Button("Reset to Inherited") { reset() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Preset").foregroundStyle(Color.primary)
                        if plus.gate.isLocked(accurateNeedsPlus) { PlusBadge() }
                    }
                    Text(errorMessage ?? detail)
                        .font(.subheadline)
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                }
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    Text(plus.gate.label(preset.displayName, needsPlus: preset == .accurate && accurateNeedsPlus))
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                .foregroundStyle(Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Gameplay Preset")
        .accessibilityValue("\(preset.displayName), \(errorMessage ?? detail)")
        .plusSheet(isPresented: $showsPlus, store: plus)
        .onAppear(perform: load)
        .onChange(of: refreshToken) { load() }
        .onChange(of: hardware) { load() }
    }

    private var accurateNeedsPlus: Bool {
        GameplayPresetValues.values(for: .accurate, hardware: hardware)?.displayFilter.needsPlus ?? false
    }

    private var detail: String {
        switch preset {
        case .raw: "Unfiltered emulated output"
        case .accurate: "Matched to \(hardware.displayName)"
        case .custom: "Advanced settings differ from Raw or Accurate"
        }
    }

    private func choose(_ newPreset: GameplayPreset) {
        guard newPreset != .custom else { return }
        if newPreset == .accurate, plus.gate.isLocked(accurateNeedsPlus) {
            showsPlus = true
            return
        }
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
''')

entitlement = Path("App/Plus/FeatureEntitlementProvider.swift")
source = entitlement.read_text().replace(
    "/// LCD 1× and LCD 3× are Plus features. Off stays free.",
    "/// Built-in display filters are Plus features. Off stays free.",
)
entitlement.write_text(source)

roadmap = Path("App/Plus/PlusRoadmap.swift")
source = roadmap.read_text().replace(
    'Item(title: "LCD Filters", detail: "LCD 1× adds a subtle pixel grid, and LCD 3× red, green and blue subpixels."),',
    'Item(title: "Display Filters", detail: "LCD filters cover handheld screens; CRT 240p and GameCube TV cover television-output models."),',
)
roadmap.write_text(source)

plus_tests = Path("AppTests/PlusTests.swift")
source = plus_tests.read_text().replace('"LCD Filters", "App Icons"', '"Display Filters", "App Icons"')
plus_tests.write_text(source)

metal_tests = Path("AppTests/LCDFilterTests.swift")
source = metal_tests.read_text()
anchor = "    /// Frame blending mixes the newest frame with the frames before it by the renderer's weights,\n"
tv_test = r'''    func testTVFiltersUseDistinctBeamStrengths() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let library = device.makeDefaultLibrary() else {
            throw XCTSkip("Metal isn't available")
        }
        for fragment in ["gameplayTextureFragment", "gameplaySharpFragment"] {
            let crt = try render(.crt240p, fragment: fragment, device: device, library: library)
            let tv = try render(.gameCubeTV, fragment: fragment, device: device, library: library)
            let edge = pixel(12, 1)
            let center = pixel(12, 12)
            let crtDrop = Int(crt[center]) - Int(crt[edge])
            let tvDrop = Int(tv[center]) - Int(tv[edge])
            XCTAssertGreaterThan(crtDrop, 0, "CRT 240p must show a visible beam profile")
            XCTAssertGreaterThan(tvDrop, 0, "GameCube TV keeps a restrained beam profile")
            XCTAssertGreaterThan(crtDrop, tvDrop, "CRT 240p must be stronger than GameCube TV")
            XCTAssertNotEqual(crt, tv)
        }
    }

'''
if anchor not in source:
    raise SystemExit("LCDFilterTests insertion anchor changed")
metal_tests.write_text(source.replace(anchor, tv_test + anchor, 1))

readme = Path("README.md")
readme.write_text(readme.read_text().replace("adds LCD filters, alternate app", "adds display filters, alternate app"))

product = Path("docs/product.md")
source = product.read_text().replace(
    "- **LCD filters**: LCD 1× and LCD 3× (see Picture).",
    "- **Display filters**: LCD 1×, LCD 3×, CRT 240p and GameCube TV (see Picture).",
)
picture_anchor = "### Picture\n\n"
picture_copy = '''### Picture

From System settings down through Game and Build, **Gameplay Preset** groups the authenticity
settings without replacing them. **Raw** removes display filtering, frame blending, display color
correction and button-contact bounce. **Accurate** writes a curated combination for the selected
Model: handheld models use their matching LCD treatment and screen colors, Super Game Boy models
use a restrained consumer 240p CRT treatment, and Game Boy Player uses a cleaner GameCube-era TV
treatment. Editing any controlled setting makes the displayed preset **Custom**; returning every
value to a built-in combination recognizes Raw or Accurate again. The preset itself is not stored,
so existing settings and App -> System -> Game -> Build inheritance keep their behavior.

'''
if picture_anchor not in source:
    raise SystemExit("product Picture anchor changed")
product.write_text(source.replace(picture_anchor, picture_copy, 1))

backlog = Path("docs/backlog.md")
source = backlog.read_text().replace(
    "the Model setting and hardware-family checks; automatic artwork previews,",
    "the Model setting and hardware-family checks; Raw/Accurate/Custom gameplay presets and model-specific display filters; automatic artwork previews,",
)
source = source.replace(
    "LCD 1× pixel grid and LCD 3× RGB subpixel effects implemented as Press Any's own code,",
    "v1.1 has Press Any's own LCD 1×/3× filters plus curated CRT 240p for Super Game Boy and GameCube TV for Game Boy Player;",
)
backlog.write_text(source)

verification = Path("docs/mvp-verification.md")
verification.write_text(verification.read_text() + '''

## v1.1 gameplay presets and television filters

- [ ] On GB, Pocket, GBC and GBA models, choose Accurate and confirm the advanced rows immediately show the documented LCD/color/blending/button values; change one and confirm the preset becomes Custom.
- [ ] Choose Raw, confirm Display Filter and Frame Blending are Off and Button Bounce is Off, then reset the preset and confirm inherited values return.
- [ ] On Super Game Boy/Super Game Boy 2, Accurate shows CRT 240p with visible but restrained scanlines/softness and no handheld LCD subpixel pattern.
- [ ] On Game Boy Player, Accurate shows the cleaner GameCube TV treatment, visibly distinct from CRT 240p and without assuming a curved or flat CRT.
- [ ] Without Plus, choosing Accurate opens Press Any Plus and does not change the stored low-level settings. Raw remains selectable.
''')

assert "public enum LCDFilter" not in settings.read_text()
assert "case .crt240p: 4" in renderer.read_text()
assert "GameplayPresetRow(" in scoped.read_text()
