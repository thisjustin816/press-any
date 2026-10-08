import Foundation
import XCTest
@testable import PressAny

final class PresentationFrameRateTests: XCTestCase {
    func testNormalConditionsAllowTheFullRateOnProMotion() {
        for thermal in [ProcessInfo.ThermalState.nominal, .fair] {
            let rate = PresentationFrameRate.policy(lowPowerMode: false, thermalState: thermal)
            XCTAssertEqual(rate, .full)
            XCTAssertEqual(rate.maximum, 120)
            XCTAssertEqual(rate.minimum, 60)
        }
    }

    func testLowPowerModeCapsPresentationAt60Hz() {
        for thermal in [ProcessInfo.ThermalState.nominal, .fair, .serious, .critical] {
            let rate = PresentationFrameRate.policy(lowPowerMode: true, thermalState: thermal)
            XCTAssertEqual(rate, .capped)
            XCTAssertEqual(rate.maximum, 60)
            XCTAssertEqual(rate.preferred, 60)
        }
    }

    func testSeriousAndCriticalHeatCapPresentationAt60Hz() {
        for thermal in [ProcessInfo.ThermalState.serious, .critical] {
            XCTAssertEqual(PresentationFrameRate.policy(lowPowerMode: false, thermalState: thermal), .capped)
        }
    }

    func testTheRangeCarriesTheRatesToTheDisplayLink() {
        XCTAssertEqual(PresentationFrameRate.capped.range.maximum, 60)
        XCTAssertEqual(PresentationFrameRate.full.range.preferred, 120)
    }
}
