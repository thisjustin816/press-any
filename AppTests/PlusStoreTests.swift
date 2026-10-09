import EmulatorDomain
import XCTest
@testable import PressAny

/// Buying, restoring and refunding Plus through `PlusStore`, with an App Store stand-in the test
/// controls. The StoreKit provider itself is checked on a device: StoreKit's test session can't
/// run on the CI simulator (docs/mvp-verification.md).
@MainActor
final class PlusStoreTests: XCTestCase {
    func testBuyingPlusUnlocksTheStoredLCDFilter() async throws {
        let provider = ControllableEntitlementProvider()
        let fixture = try LCDFixture(plus: PlusStore(provider: provider))
        defer { fixture.remove() }
        let plus = fixture.container.plus
        await plus.refreshOwnership()
        XCTAssertFalse(plus.isUnlocked)
        XCTAssertEqual(fixture.container.lcdFilter(for: fixture.context), .off)

        await plus.loadOffer()
        XCTAssertEqual(plus.offer, .available(price: "$0.99"), "the price comes from the store")

        await plus.buy()
        XCTAssertNil(plus.notice)
        XCTAssertTrue(plus.isUnlocked)
        XCTAssertTrue(plus.ownership.isOwned, "game sessions see it too")
        XCTAssertEqual(fixture.container.lcdFilter(for: fixture.context), .lcd1x)
    }

    func testAPurchaseWaitingForApprovalStaysLockedAndSaysSo() async {
        let provider = ControllableEntitlementProvider()
        provider.purchase = .success(.pending)
        let plus = PlusStore(provider: provider)
        await plus.buy()
        XCTAssertFalse(plus.isUnlocked)
        XCTAssertEqual(plus.notice, "Your purchase is waiting for approval. Plus unlocks once it’s approved.")
    }

    func testCancellingAPurchaseSaysNothing() async {
        let provider = ControllableEntitlementProvider()
        provider.purchase = .success(.cancelled)
        let plus = PlusStore(provider: provider)
        await plus.buy()
        XCTAssertFalse(plus.isUnlocked)
        XCTAssertNil(plus.notice)
    }

    func testAFailedPurchaseSaysSoAndStaysLocked() async {
        let provider = ControllableEntitlementProvider()
        provider.purchase = .failure(StoreOffline())
        let plus = PlusStore(provider: provider)
        await plus.buy()
        XCTAssertFalse(plus.isUnlocked)
        XCTAssertEqual(plus.notice, "The purchase didn’t go through. The store is offline.")
        XCTAssertFalse(plus.isBusy)
    }

    func testRestoreFindsAnEarlierPurchase() async {
        let provider = ControllableEntitlementProvider()
        provider.ownedAfterRestore = true
        let plus = PlusStore(provider: provider)
        await plus.restore()
        XCTAssertTrue(plus.isUnlocked)
        XCTAssertNil(plus.notice)
    }

    func testRestoreWithoutAPurchaseSaysSo() async {
        let plus = PlusStore(provider: ControllableEntitlementProvider())
        await plus.restore()
        XCTAssertFalse(plus.isUnlocked)
        XCTAssertEqual(plus.notice, "No \(PlusProduct.name) purchase was found for this Apple Account.")
    }

    func testRestoreThatCantReachTheStoreSaysSo() async {
        let provider = ControllableEntitlementProvider()
        provider.restoreError = StoreOffline()
        let plus = PlusStore(provider: provider)
        await plus.restore()
        XCTAssertFalse(plus.isUnlocked)
        XCTAssertEqual(plus.notice, "Couldn’t reach the App Store to restore. The store is offline.")
    }

    func testCancellingTheSignInDuringRestoreSaysNothing() async {
        let provider = ControllableEntitlementProvider()
        provider.restoreError = CancellationError()
        let plus = PlusStore(provider: provider)
        await plus.restore()
        XCTAssertFalse(plus.isUnlocked)
        XCTAssertNil(plus.notice)
    }

    func testRefundLocksPlusAgainAndKeepsTheStoredFilter() async throws {
        let provider = ControllableEntitlementProvider()
        let fixture = try LCDFixture(plus: PlusStore(provider: provider))
        defer { fixture.remove() }
        let plus = fixture.container.plus
        await plus.buy()
        XCTAssertEqual(fixture.container.lcdFilter(for: fixture.context), .lcd1x)

        // The store reports a refund on its own, as StoreKit's updates do.
        provider.changeOwnership(to: false)
        try await waitUntil { !plus.isUnlocked }

        XCTAssertFalse(plus.ownership.isOwned)
        XCTAssertEqual(fixture.container.lcdFilter(for: fixture.context), .off)
        XCTAssertEqual(try fixture.storedFilter(), .lcd1x, "a refund doesn't delete the choice")
    }

    func testAPurchaseOnAnotherDeviceUnlocksWithoutARestart() async throws {
        let provider = ControllableEntitlementProvider()
        let plus = PlusStore(provider: provider)
        await plus.refreshOwnership()
        XCTAssertFalse(plus.isUnlocked)
        provider.changeOwnership(to: true)
        try await waitUntil { plus.isUnlocked }
        XCTAssertTrue(plus.ownership.isOwned)
    }

    func testAFailedProductLoadShowsTheMessageAndTryAgainRecovers() async {
        let provider = ControllableEntitlementProvider()
        provider.priceError = StoreOffline()
        let plus = PlusStore(provider: provider)
        await plus.loadOffer()
        XCTAssertEqual(plus.offer, .unavailable, "PlusView shows its unavailable message for this")
        XCTAssertFalse(PlusView.unavailableMessage.isEmpty)

        provider.priceError = nil
        await plus.loadOffer()
        XCTAssertEqual(plus.offer, .available(price: "$0.99"), "Try Again loads the product")
    }

    func testAProductTheStoreDoesntOfferIsUnavailable() async {
        let provider = ControllableEntitlementProvider()
        provider.price = nil
        let plus = PlusStore(provider: provider)
        await plus.loadOffer()
        XCTAssertEqual(plus.offer, .unavailable)
    }

    func testOwnershipIsUnresolvedUntilTheStoreHasAnswered() async {
        let plus = PlusStore(provider: ControllableEntitlementProvider())
        XCTAssertFalse(plus.ownership.isOwned)
        XCTAssertFalse(plus.ownership.isResolved)
        XCTAssertTrue(plus.ownership.keepsAutoStateHistory, "an unanswered question deletes nothing")
        await plus.refreshOwnership()
        XCTAssertTrue(plus.ownership.isResolved)
        XCTAssertFalse(plus.ownership.keepsAutoStateHistory)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("Timed out waiting for the store's change") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private struct StoreOffline: LocalizedError {
    var errorDescription: String? { "The store is offline." }
}

/// An App Store the test controls: what it owns, what it charges, and how a purchase or restore ends.
@MainActor
private final class ControllableEntitlementProvider: FeatureEntitlementProvider {
    private(set) var owned = false
    var price: String? = "$0.99"
    var priceError: Error?
    var purchase: Result<PlusPurchaseResult, Error> = .success(.purchased)
    var ownedAfterRestore = false
    var restoreError: Error?
    private var changes: AsyncStream<Bool>.Continuation?

    func ownsPlus() async -> Bool { owned }

    func ownershipChanges() -> AsyncStream<Bool> {
        AsyncStream { changes = $0 }
    }

    /// A change from outside the app, such as a refund or a purchase on another device.
    func changeOwnership(to owned: Bool) {
        self.owned = owned
        changes?.yield(owned)
    }

    func plusDisplayPrice() async throws -> String? {
        if let priceError { throw priceError }
        return price
    }

    func purchasePlus() async throws -> PlusPurchaseResult {
        let result = try purchase.get()
        if result == .purchased { owned = true }
        return result
    }

    func restorePurchases() async throws {
        if let restoreError { throw restoreError }
        if ownedAfterRestore { owned = true }
    }
}
