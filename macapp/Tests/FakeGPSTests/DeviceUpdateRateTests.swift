import CoreLocation
import XCTest
@testable import FakeGPS

@MainActor
final class DeviceUpdateRateTests: XCTestCase {
    private let road = [Waypoint(coordinate: .init(latitude: 0, longitude: 0)),
                        Waypoint(coordinate: .init(latitude: 0, longitude: 0.01))]
    private let script = #"""
import json, sys
print(json.dumps({'event': 'ready', 'device': {'udid': 'test'}}), flush=True)
for line in sys.stdin:
    command = json.loads(line)
    if command['cmd'] == 'set' and len(sys.argv) > 1:
        with open(sys.argv[1], 'a') as output:
            output.write('set\n')
    if command['cmd'] == 'quit':
        break
    print(json.dumps({'event': 'ok', 'id': command.get('id')}), flush=True)
"""#

    private func helper(log: URL? = nil) async throws -> Sidecar {
        let sidecar = Sidecar(executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                              argsPrefix: ["-u", "-c", script] + (log.map { [$0.path] } ?? []))
        sidecar.start()
        for _ in 0..<100 {
            if sidecar.state.isReady { return sidecar }
            try await Task.sleep(for: .milliseconds(20))
        }
        sidecar.stop()
        throw NSError(domain: "Helper failed to start", code: 1)
    }

    func testTenHzPreservesTravelSpeedWithoutGPSVariation() async throws {
        let sidecar = try await helper()
        defer { sidecar.stop() }
        var clock: TimeInterval = 0
        let engine = SimulationEngine(sidecar: sidecar, now: { clock })
        defer { engine.stop() }
        engine.waypoints = road
        engine.speedKmh = 36
        engine.play()
        XCTAssertEqual(engine.currentCoordinate?.longitude, 0)
        for _ in 0..<20 {
            clock += 0.1
            engine.step()
            XCTAssertEqual(engine.currentCoordinate?.latitude, 0)
        }
        XCTAssertEqual(Geo.distance(road[0].coordinate, try XCTUnwrap(engine.currentCoordinate)), 20, accuracy: 0.001)
    }

    func testPausingDoesNotResetOrSkipDistance() async throws {
        let sidecar = try await helper()
        defer { sidecar.stop() }
        var clock: TimeInterval = 0
        let engine = SimulationEngine(sidecar: sidecar, now: { clock })
        defer { engine.stop() }
        engine.waypoints = road
        engine.speedKmh = 36
        engine.play()
        clock = 0.5
        engine.step()
        XCTAssertEqual(Geo.distance(road[0].coordinate, try XCTUnwrap(engine.currentCoordinate)), 5, accuracy: 0.001)
        clock = 0.6
        engine.step()
        engine.pause()
        clock = 100
        engine.play()
        clock = 100.2
        engine.step()
        XCTAssertEqual(Geo.distance(road[0].coordinate, try XCTUnwrap(engine.currentCoordinate)), 8, accuracy: 0.001)
        clock = 102.2 // A late timer callback must use elapsed time.
        engine.step()
        XCTAssertEqual(Geo.distance(road[0].coordinate, try XCTUnwrap(engine.currentCoordinate)), 28, accuracy: 0.001)
    }

    func testFixedTenHzWritesAndStopCancelsThem() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: log) }
        let sidecar = try await helper(log: log)
        defer { sidecar.stop() }
        let engine = SimulationEngine(sidecar: sidecar)
        defer { engine.stop() }
        engine.waypoints = road
        engine.play()
        try await Task.sleep(for: .milliseconds(750))
        engine.stop()
        try await Task.sleep(for: .milliseconds(150)) // Let the helper drain its pipe.
        let lines = try String(contentsOf: log).split(separator: "\n").count
        XCTAssertGreaterThanOrEqual(lines, 5, "10 Hz should produce several writes before the original 1 Hz timer would fire")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(try String(contentsOf: log).split(separator: "\n").count, lines)
    }
}
