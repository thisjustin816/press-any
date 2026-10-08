import EmulatorDomain
import Foundation
import StoreKit

/// The one-time purchase that unlocks Plus features. Its price is set in App Store Connect.
enum PlusProduct {
    static let id = "com.thisjustin816.PressAny.plus"
    static var name: String { "\(AppBrand.displayName) Plus" }
}

enum PlusPurchaseResult: Equatable, Sendable {
    case purchased
    /// Waiting on Ask to Buy or another approval. `Transaction.updates` delivers it later.
    case pending
    case cancelled
}

/// Where Plus ownership and its product come from: StoreKit in the app, or a fixed answer for tests,
/// screenshot runs and UI tests. Domain, core, storage and import code never see it.
@MainActor
protocol FeatureEntitlementProvider {
    /// Whether Plus is owned now. StoreKit answers from its on-device cache, so this works offline.
    func ownsPlus() async -> Bool
    /// Ownership after each change from outside a purchase in the app: a purchase on another
    /// device, an approved Ask to Buy, a Family Sharing change, a refund or a revocation.
    func ownershipChanges() -> AsyncStream<Bool>
    /// The localized price, or nil when the App Store doesn't offer the product.
    func plusDisplayPrice() async throws -> String?
    func purchasePlus() async throws -> PlusPurchaseResult
    /// Throws `CancellationError` when the person cancels signing in.
    func restorePurchases() async throws
}

struct StoreKitEntitlementProvider: FeatureEntitlementProvider {
    var productID = PlusProduct.id

    enum Failure: LocalizedError {
        case unavailable
        case unverified

        var errorDescription: String? {
            switch self {
            case .unavailable: "The App Store isn’t offering this purchase right now."
            case .unverified: "The App Store couldn’t confirm the purchase."
            }
        }
    }

    func ownsPlus() async -> Bool {
        // Refunded and revoked purchases leave the current entitlements; the revocation date is
        // checked too, in case one is still listed.
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == productID,
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    func ownershipChanges() -> AsyncStream<Bool> {
        let provider = self
        return AsyncStream { continuation in
            let task = Task {
                // A purchase can complete while the app isn't running to finish it.
                for await result in Transaction.unfinished {
                    await Self.finish(result)
                }
                for await result in Transaction.updates {
                    await Self.finish(result)
                    continuation.yield(await provider.ownsPlus())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func plusDisplayPrice() async throws -> String? {
        try await Product.products(for: [productID]).first?.displayPrice
    }

    func purchasePlus() async throws -> PlusPurchaseResult {
        guard let product = try await Product.products(for: [productID]).first else { throw Failure.unavailable }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result else { throw Failure.unverified }
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restorePurchases() async throws {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            throw CancellationError()
        }
    }

    /// Unverified transactions stay unfinished and never count as ownership.
    private static func finish(_ result: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = result {
            await transaction.finish()
        }
    }
}

/// Ownership that never changes, with no product to buy: tests, and Debug runs that grant Plus.
struct FixedEntitlementProvider: FeatureEntitlementProvider {
    let owns: Bool

    func ownsPlus() async -> Bool { owns }
    func ownershipChanges() -> AsyncStream<Bool> { AsyncStream { $0.finish() } }
    func plusDisplayPrice() async throws -> String? { nil }
    func purchasePlus() async throws -> PlusPurchaseResult { throw StoreKitEntitlementProvider.Failure.unavailable }
    func restorePurchases() async throws {}
}

extension LCDFilter {
    /// LCD 1× and LCD 3× are Plus features. Off stays free.
    var needsPlus: Bool { self != .off }
}
