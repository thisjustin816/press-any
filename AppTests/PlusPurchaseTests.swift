import EmulatorDomain
import StoreKit
import StoreKitTest
import XCTest
@testable import PressAny

/// Buying, restoring and refunding Plus against Config/PressAnyPlus.storekit, through the same
/// StoreKit provider the app uses.
@MainActor
final class PlusPurchaseTests: XCTestCase {
    /// Held for the whole test: StoreKit goes back to the real App Store once it's released.
    private var session: SKTestSession?

    func testBuyingPlusUnlocksTheStoredLCDFilter() async throws {
        try startSession()
        let fixture = try LCDFixture(plus: PlusStore(provider: StoreKitEntitlementProvider()))
        defer { fixture.remove() }
        let plus = fixture.container.plus
        await plus.refreshOwnership()
        XCTAssertFalse(plus.isUnlocked)
        XCTAssertEqual(fixture.container.lcdFilter(for: fixture.context), .off)

        await plus.loadOffer()
        guard case .available(let price) = plus.offer else { return XCTFail("The product loads, not \(plus.offer)") }
        XCTAssertTrue(price.contains("0.99"), "the price comes from the configuration: \(price)")

        await plus.buy()
        XCTAssertNil(plus.notice)
        XCTAssertTrue(plus.isUnlocked)
        XCTAssertTrue(plus.ownership.isOwned, "game sessions see it too")
        XCTAssertEqual(fixture.container.lcdFilter(for: fixture.context), .lcd1x)
    }

    func testRestoreFindsAnEarlierPurchase() async throws {
        let session = try startSession()
        try await session.buyProduct(identifier: PlusProduct.id)
        let plus = PlusStore(provider: StoreKitEntitlementProvider())
        await plus.restore()
        XCTAssertTrue(plus.isUnlocked)
        XCTAssertNil(plus.notice)
    }

    func testRestoreWithoutAPurchaseSaysSo() async throws {
        try startSession()
        let plus = PlusStore(provider: StoreKitEntitlementProvider())
        await plus.restore()
        XCTAssertFalse(plus.isUnlocked)
        XCTAssertEqual(plus.notice, "No \(PlusProduct.name) purchase was found for this Apple Account.")
    }

    func testRefundLocksPlusAgainAndKeepsTheStoredFilter() async throws {
        let session = try startSession()
        let fixture = try LCDFixture(plus: PlusStore(provider: StoreKitEntitlementProvider()))
        defer { fixture.remove() }
        let plus = fixture.container.plus
        await plus.loadOffer()
        await plus.buy()
        XCTAssertEqual(fixture.container.lcdFilter(for: fixture.context), .lcd1x)

        let purchase = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == PlusProduct.id })
        try session.refundTransaction(identifier: purchase.identifier)
        // Only the store's own Transaction.updates listener can notice this.
        try await waitUntil { !plus.isUnlocked }

        XCTAssertFalse(plus.ownership.isOwned)
        XCTAssertEqual(fixture.container.lcdFilter(for: fixture.context), .off)
        XCTAssertEqual(try fixture.storedFilter(), .lcd1x, "a refund doesn't delete the choice")
    }

    func testAFailedProductLoadShowsTheMessageAndTryAgainRecovers() async throws {
        let session = try startSession()
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        let plus = PlusStore(provider: StoreKitEntitlementProvider())
        await plus.loadOffer()
        XCTAssertEqual(plus.offer, .unavailable, "PlusView shows its unavailable message for this")
        XCTAssertFalse(PlusView.unavailableMessage.isEmpty)

        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await plus.loadOffer()
        guard case .available = plus.offer else { return XCTFail("Try Again loads the product, not \(plus.offer)") }
    }

    func testAProductTheStoreDoesntOfferIsUnavailable() async throws {
        try startSession()
        let plus = PlusStore(provider: StoreKitEntitlementProvider(productID: "com.thisjustin816.PressAny.missing"))
        await plus.loadOffer()
        XCTAssertEqual(plus.offer, .unavailable)
    }

    @discardableResult
    private func startSession() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PressAnyPlus", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        self.session = session
        return session
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("Timed out waiting for the refund to arrive") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
