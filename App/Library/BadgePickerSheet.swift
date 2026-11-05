import EmulatorApplication
import EmulatorDomain
import SwiftUI

/// Chooses a profile's badge from a grid of emoji. iOS gives an app no emoji picker, and a text
/// field takes anything typed, so the sheet offers only emoji that `SetSaveProfileBadge` accepts.
struct BadgePickerSheet: View {
    let profile: SaveProfile
    /// Called with the chosen emoji, or nil to remove the badge. The sheet closes after it.
    let choose: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 4)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Shown before the name of this save")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Text(profile.title)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                    ForEach(SaveProfileBadgeCatalog.groups) { group in
                        groupSection(group)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Badge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if profile.badge != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Remove", role: .destructive) {
                            choose(nil)
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func groupSection(_ group: SaveProfileBadgeCatalog.Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(group.emoji, id: \.self) { emoji in
                    Button {
                        choose(emoji)
                        dismiss()
                    } label: {
                        Text(emoji)
                            .font(.largeTitle)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                emoji == profile.badge ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(emoji == profile.badge ? .isSelected : [])
                }
            }
            .padding(8)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
