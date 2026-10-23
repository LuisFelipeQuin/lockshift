import XCTest
@testable import FakeGPS

final class RestoreLocationTests: XCTestCase {
    // Exercises the real process/JSON transport without touching an iPhone.
    private static let helper = #"""
import json, sys, time
print(json.dumps({"event": "ready", "device": {"udid": "test"}}), flush=True)
for line in sys.stdin:
    command = json.loads(line)
    if command['cmd'] == 'clear':
        time.sleep(0.1)
        if sys.argv[1] == 'error':
            print(json.dumps({'event': 'error', 'id': command.get('id'), 'message': 'Reset rejected', 'fatal': False}), flush=True)
        else:
            print(json.dumps({'event': 'ok', 'id': command.get('id')}), flush=True)
    elif command['cmd'] == 'set':
        print(json.dumps({'event': 'error', 'message': 'Unexpected location write during restore', 'fatal': True}), flush=True)
    elif command['cmd'] == 'quit':
        time.sleep(0.2)
        break
"""#

    @MainActor
    private func makeSidecar(response: String) async throws -> Sidecar {
        let sidecar = Sidecar(executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                              argsPrefix: ["-u", "-c", Self.helper, response])
        sidecar.start()
        for _ in 0..<100 {
            if sidecar.state.isReady { return sidecar }
            try await Task.sleep(for: .milliseconds(25))
        }
        sidecar.stop()
        throw NSError(domain: "Test helper did not start", code: 1)
    }

    @MainActor
    func testRestoreWaitsForAcknowledgementAndClosesSession() async throws {
        let sidecar = try await makeSidecar(response: "ok")
        defer { sidecar.stop() }
        let restore = Task { await sidecar.restoreLocation() }
        while !sidecar.isRestoring { await Task.yield() }
        // A queued playback tick must not put the phone back into simulation.
        sidecar.setLocation(1, 2)
        let restored = await restore.value
        XCTAssertTrue(restored)
        XCTAssertEqual(sidecar.state, .stopped)
        XCTAssertFalse(sidecar.isRestoring)
        XCTAssertNil(sidecar.lastError)
    }

    @MainActor
    func testDeviceSwitchWaitsForPreviousHelperToExit() async throws {
        let sidecar = try await makeSidecar(response: "ok")
        defer { sidecar.stop() }
        let start = ContinuousClock.now
        let closed = await sidecar.disconnectAndWait()
        XCTAssertTrue(closed)
        XCTAssertEqual(sidecar.state, .stopped)
        // The fixture spends 0.1 seconds clearing and 0.2 seconds closing.
        XCTAssertGreaterThanOrEqual(start.duration(to: .now), .milliseconds(250))
    }

    @MainActor
    func testRejectedResetDoesNotReportSuccessOrCloseUsableSession() async throws {
        let sidecar = try await makeSidecar(response: "error")
        defer { sidecar.stop() }
        let restored = await sidecar.restoreLocation()
        XCTAssertFalse(restored)
        XCTAssertTrue(sidecar.state.isReady)
        XCTAssertFalse(sidecar.isRestoring)
        XCTAssertEqual(sidecar.lastError, "Reset rejected")
    }
}
