import Combine
import EmulatorDomain
import Foundation

/// Whether Plus is owned, and the purchase and restore the Plus screen offers. Ownership is read at
/// launch and follows every transaction update, so a purchase, a refund or a Family Sharing change
/// takes effect without a restart.
@MainActor
final class PlusStore: ObservableObject {
    enum Offer: Equatable {
        case loading
        case available(price: String)
        /// Offline, signed out of the App Store, or not offered in this storefront.
        case unavailable
    }

    @Published private(set) var isUnlocked: Bool {
        didSet { ownership.set(isUnlocked) }
    }
    @Published private(set) var offer: Offer = .loading
    /// A purchase or restore is running.
    @Published private(set) var isBusy = false
    /// What the last purchase or restore found, when there's something to say.
    @Published private(set) var notice: String?

    /// The same as `isUnlocked`, for a game session to read off the main actor.
    nonisolated let ownership: PlusOwnership

    private let provider: any FeatureEntitlementProvider

    /// `ownsPlus` is what shows until the provider first answers.
    init(provider: any FeatureEntitlementProvider, ownsPlus: Bool = false) {
        self.provider = provider
        // Only a provider that already knows its answer starts resolved. StoreKit's isn't known
        // until it has been asked.
        ownership = PlusOwnership(ownsPlus, resolved: provider is FixedEntitlementProvider)
        isUnlocked = ownsPlus
        // Subscribed before the first read, so a change between the two isn't missed.
        let changes = provider.ownershipChanges()
        Task { [weak self] in
            await self?.refreshOwnership()
            for await owned in changes {
                guard let self else { return }
                isUnlocked = owned
            }
        }
    }

    static func fixed(ownsPlus: Bool) -> PlusStore {
        PlusStore(provider: FixedEntitlementProvider(owns: ownsPlus), ownsPlus: ownsPlus)
    }

    /// StoreKit, unless a Debug launch argument grants Plus.
    static func live() -> PlusStore {
        if ScreenshotScene.grantsPlus { return fixed(ownsPlus: true) }
        return PlusStore(provider: StoreKitEntitlementProvider())
    }

    var gate: PlusGate { PlusGate(isUnlocked: isUnlocked) }

    /// The filter a game shows: a Plus filter plays as Off without Plus. The stored setting is
    /// left alone, so buying or restoring Plus brings it back.
    func effective(_ filter: LCDFilter) -> LCDFilter {
        gate.isLocked(filter.needsPlus) ? .off : filter
    }

    func refreshOwnership() async {
        isUnlocked = await provider.ownsPlus()
    }

    func loadOffer() async {
        offer = .loading
        do {
            offer = try await provider.plusDisplayPrice().map { .available(price: $0) } ?? .unavailable
        } catch {
            offer = .unavailable
        }
    }

    func buy() async {
        guard !isBusy else { return }
        isBusy = true
        notice = nil
        defer { isBusy = false }
        do {
            switch try await provider.purchasePlus() {
            case .purchased:
                await refreshOwnership()
            case .pending:
                notice = "Your purchase is waiting for approval. Plus unlocks once it’s approved."
            case .cancelled:
                break
            }
        } catch {
            notice = "The purchase didn’t go through. \(error.localizedDescription)"
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        notice = nil
        defer { isBusy = false }
        do {
            try await provider.restorePurchases()
        } catch is CancellationError {
            return
        } catch {
            notice = "Couldn’t reach the App Store to restore. \(error.localizedDescription)"
            return
        }
        await refreshOwnership()
        if !isUnlocked {
            notice = "No \(PlusProduct.name) purchase was found for this Apple Account."
        }
    }
}

/// Plus ownership behind a lock, so a game session's thread can check it at each Auto State write.
final class PlusOwnership: @unchecked Sendable {
    private let lock = NSLock()
    private var owned: Bool
    private var resolved: Bool

    init(_ owned: Bool, resolved: Bool = true) {
        self.owned = owned
        self.resolved = resolved
    }

    var isOwned: Bool { lock.withLock { owned } }

    /// Whether the provider has answered yet. Until it has, `isOwned` only means "not asked".
    var isResolved: Bool { lock.withLock { resolved } }

    /// Whether to keep more than the newest Auto State. Deleting a paying owner's states because
    /// StoreKit hasn't answered yet at launch can't be undone, so an unanswered question keeps them.
    var keepsAutoStateHistory: Bool { lock.withLock { owned || !resolved } }

    func set(_ owned: Bool) {
        lock.withLock {
            self.owned = owned
            resolved = true
        }
    }
}

/// How a setting with Plus values behaves without Plus: those values stay listed, marked Plus, and
/// choosing one opens the Plus screen instead of saving it.
struct PlusGate: Equatable {
    let isUnlocked: Bool

    func isLocked(_ needsPlus: Bool) -> Bool {
        needsPlus && !isUnlocked
    }

    /// A menu item's text. Menus show text only, so the badge is the word.
    func label(_ name: String, needsPlus: Bool) -> String {
        isLocked(needsPlus) ? "\(name) (Plus)" : name
    }

    /// How many unpinned Auto States a game keeps: the chosen number with Plus, the newest without.
    func keptAutoStates(_ choice: KeepAutoStates) -> Int {
        isLocked(choice.needsPlus) ? 1 : choice.rawValue
    }
}
