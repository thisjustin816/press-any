import UIKit
import XCTest
@testable import PressAny

@MainActor
final class ScrollOverflowObserverTests: XCTestCase {
    func testScrollContentSizeInsetsAndViewportUpdateTheCue() async {
        let host = Host()
        host.scrollView.contentSize.height = 900
        await settle()
        XCTAssertEqual(host.values.last, true)

        host.scrollView.contentOffset.y = 300
        await settle()
        XCTAssertEqual(host.values.last, false)

        host.scrollView.contentInset.bottom = 80
        await settle()
        XCTAssertEqual(host.values.last, true)

        host.scrollView.contentSize.height = 400
        host.scrollView.contentOffset.y = 0
        await settle()
        XCTAssertEqual(host.values.last, false)

        host.scrollView.frame.size.height = 300
        await settle()
        XCTAssertEqual(host.values.last, true)
    }

    func testProbeUsesItsLocalScrollViewAndStopsWhenRemoved() async {
        let host = Host()
        let unrelated = UIScrollView(frame: host.container.bounds)
        unrelated.contentSize.height = 2_000
        host.window.insertSubview(unrelated, belowSubview: host.container)
        host.scrollView.contentSize.height = 200
        await settle()
        XCTAssertEqual(host.values, [false])

        host.probe.removeFromSuperview()
        host.scrollView.contentSize.height = 1_000
        await settle()
        XCTAssertEqual(host.values, [false], "removed probes must release their observations")

        host.container.addSubview(host.probe)
        await settle()
        XCTAssertEqual(host.values, [false, true])
    }

    func testUnchangedGeometryDoesNotRepeatNotifications() async {
        let host = Host()
        host.scrollView.contentSize.height = 1_000
        await settle()
        host.scrollView.contentOffset.y = 50
        host.scrollView.contentOffset.y = 100
        host.probe.scheduleConnection()
        await settle()
        XCTAssertEqual(host.values, [true])
    }

    private func settle() async {
        for _ in 0..<4 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @MainActor
    private final class Host {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        lazy var probe = ScrollOverflowProbe { [weak self] in self?.values.append($0) }
        var values: [Bool] = []

        init() {
            scrollView.contentInsetAdjustmentBehavior = .never
            window.addSubview(container)
            container.addSubview(scrollView)
            probe.frame = container.bounds
            container.addSubview(probe)
        }
    }
}
