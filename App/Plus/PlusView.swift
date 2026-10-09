import SwiftUI

/// Settings > Press Any Plus: what Plus includes now, the roadmap it promises, and Buy and Restore.
/// A locked option opens it as a sheet, once per tap.
struct PlusView: View {
    @ObservedObject var store: PlusStore
    /// False when App Settings pushes it as a page, which has its own navigation.
    var inSheet = false

    @Environment(\.dismiss) private var dismiss

    static let unavailableMessage = "The App Store isn’t available right now. Check your internet connection and that you’re signed in to the App Store, then try again."

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
            Section {
                if store.isUnlocked {
                    Label("Thank you for buying \(PlusProduct.name). Everything below is yours, and so is everything on the roadmap as it arrives.", systemImage: "heart.fill")
                        .accessibilityIdentifier("plus.thanks")
                } else {
                    Text("One purchase that unlocks extra features, now and later. Everything that’s free stays free: playing, saves, save states, backups and exports.")
                }
            }

            Section("Included Now") {
                ForEach(PlusRoadmap.includedToday) { PlusItemRow(item: $0) }
            }

            if !store.isUnlocked {
                purchaseSection
            }

            Section {
                ForEach(PlusRoadmap.upcoming) { PlusItemRow(item: $0) }
            } header: {
                Text("On the Roadmap")
            } footer: {
                Text("Plus includes everything on this list and anything added later, at no extra cost. Some of it will be free for everyone, too.")
            }
        }
        .navigationTitle(PlusProduct.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !store.isUnlocked { await store.loadOffer() }
        }
    }

    private var purchaseSection: some View {
        Section {
            switch store.offer {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .available(let price):
                Button {
                    Task { await store.buy() }
                } label: {
                    HStack {
                        Text("Buy \(PlusProduct.name)")
                        Spacer()
                        if store.isBusy {
                            ProgressView()
                        } else {
                            Text(price).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(store.isBusy)
                .accessibilityIdentifier("plus.buy")
            case .unavailable:
                Text(Self.unavailableMessage)
                    .accessibilityIdentifier("plus.unavailable")
                Button("Try Again") { Task { await store.loadOffer() } }
            }
            Button("Restore Purchases") { Task { await store.restore() } }
                .disabled(store.isBusy)
            if let notice = store.notice {
                Text(notice)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Buy once and keep it on every device signed in to your Apple Account, and share it with Family Sharing. The price goes up when version 1.1 ships.")
        }
    }
}

private struct PlusItemRow: View {
    let item: PlusRoadmap.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
            Text(item.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Marks a Plus feature or option beside its name.
struct PlusBadge: View {
    var body: some View {
        Text("Plus")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(uiColor: AppBrand.Wordmark.accent)))
            .accessibilityLabel("Plus feature")
    }
}

extension View {
    /// The Plus screen as a sheet, for a locked option's tap.
    func plusSheet(isPresented: Binding<Bool>, store: PlusStore) -> some View {
        sheet(isPresented: isPresented) {
            PlusView(store: store, inSheet: true)
        }
    }

    /// Runs `action` after Plus is bought, restored, refunded or revoked, for a view that doesn't
    /// otherwise observe the store.
    func onPlusChange(_ store: PlusStore, perform action: @escaping () -> Void) -> some View {
        modifier(PlusChangeObserver(store: store, action: action))
    }
}

private struct PlusChangeObserver: ViewModifier {
    @ObservedObject var store: PlusStore
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: store.isUnlocked) { _, _ in action() }
    }
}
