import XCTest
@testable import FakeGPS

final class RouteDisplayTests: XCTestCase {
    func testMilesAndHourRollover() {
        XCTAssertEqual(RouteDisplay.distance(metres: 1609.344), "1.00 mi")
        XCTAssertEqual(RouteDisplay.duration(seconds: 30), "1 min")
        XCTAssertEqual(RouteDisplay.duration(seconds: 59 * 60), "59 min")
        XCTAssertEqual(RouteDisplay.duration(seconds: 59 * 60 + 40), "1 h 0 min")
        XCTAssertEqual(RouteDisplay.duration(seconds: 90 * 60), "1 h 30 min")
        XCTAssertEqual(RouteDisplay.duration(seconds: 2 * 3600 + 5 * 60), "2 h 5 min")
    }

    @MainActor func testMphConversionPreservesEngineSpeedAndDuration() {
        let sidecar = Sidecar(executableURL: URL(fileURLWithPath: "/usr/bin/false"), argsPrefix: [])
        let engine = SimulationEngine(sidecar: sidecar)
        engine.speedMph = 60
        XCTAssertEqual(engine.speedKmh, 96.56064, accuracy: 0.00001)
        XCTAssertEqual(engine.speedMph, 60, accuracy: 0.00001)
    }
}

final class SpeedPresetTests: XCTestCase {
    func testPresetsMatchTheirOwnSpeed() {
        for preset in SpeedPreset.allCases {
            XCTAssertEqual(SpeedPreset.matching(speedKmh: preset.speedKmh), preset)
        }
    }

    func testCustomSpeedsStayInsideTheirBand() {
        XCTAssertEqual(SpeedPreset.matching(speedKmh: 1), .walk)          // below walk
        XCTAssertEqual(SpeedPreset.matching(speedKmh: 12), .walk)         // between walk and cycle
        XCTAssertEqual(SpeedPreset.matching(speedKmh: 30), .cycle)        // between cycle and drive
        XCTAssertEqual(SpeedPreset.matching(speedKmh: 100 * 1.609344), .drive) // 100 mph
        XCTAssertEqual(SpeedPreset.matching(speedKmh: 300), .drive)       // slider maximum
    }
}
