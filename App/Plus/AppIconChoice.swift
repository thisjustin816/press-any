import SwiftUI
import UIKit

/// The home-screen icon: the default, or a Plus colorway of it. Each colorway is an app icon set
/// in the asset catalog, with a small preview image set beside it.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard
    case berry
    case grape
    case teal
    case kiwi
    case dandelion

    var id: String { rawValue }

    var title: String { self == .standard ? "Default" : rawValue.capitalized }

    /// The alternate icon's asset name, or nil for the primary icon.
    var iconName: String? { self == .standard ? nil : "AppIcon-\(title)" }

    var previewName: String { "AppIconPreview-\(title)" }

    var needsPlus: Bool { self != .standard }

    /// The choice for `UIApplication.alternateIconName`. An unknown name reads as the default.
    init(iconName: String?) {
        self = Self.allCases.first { $0.iconName == iconName } ?? .standard
    }
}

/// Settings > App Icon. Without Plus the colorways stay listed, marked Plus, and choosing one opens
/// the Plus screen. Losing Plus leaves the current icon alone, since iOS alerts on every change.
struct AppIconSettingsPage: View {
    @ObservedObject var plus: PlusStore

    @State private var current = AppIconChoice(iconName: UIApplication.shared.alternateIconName)
    @State private var showsPlus = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                ForEach(AppIconChoice.allCases) { choice in
                    Button {
                        choose(choice)
                    } label: {
                        HStack(spacing: 14) {
                            Image(choice.previewName)
                                .resizable()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                                .accessibilityHidden(true)
                            Text(choice.title)
                                .foregroundStyle(Color.primary)
                            if plus.gate.isLocked(choice.needsPlus) {
                                PlusBadge()
                            }
                            Spacer()
                            if choice == current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .accessibilityAddTraits(choice == current ? .isSelected : [])
                }
            } footer: {
                Text(plus.isUnlocked
                     ? "iOS confirms each change with a message."
                     : "The colors come with \(PlusProduct.name). An icon you already chose stays until you change it.")
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .plusSheet(isPresented: $showsPlus, store: plus)
    }

    private func choose(_ choice: AppIconChoice) {
        guard choice != current else { return }
        guard !plus.gate.isLocked(choice.needsPlus) else {
            showsPlus = true
            return
        }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(choice.iconName)
                current = choice
                errorMessage = nil
            } catch {
                errorMessage = "Couldn’t change the icon. \(error.localizedDescription)"
            }
        }
    }
}
