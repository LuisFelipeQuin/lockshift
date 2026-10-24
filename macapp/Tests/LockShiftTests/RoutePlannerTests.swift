import MapKit
import XCTest
@testable import LockShift

@MainActor
final class RoutePlannerTests: XCTestCase {
    private let start = RoutePlace(title: "Start", coordinate: .init(latitude: 40, longitude: -74))
    private let end = RoutePlace(title: "End", coordinate: .init(latitude: 41, longitude: -73))

    private func finish(_ planner: RoutePlanner) async throws {
        for _ in 0..<200 {
            if !planner.isLoading { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Route calculation did not finish")
    }

    func testKeepsStreetGeometryInsteadOfConnectingEndpointsDirectly() async throws {
        let bend = CLLocationCoordinate2D(latitude: 40, longitude: -73)
        let planner = RoutePlanner { from, to in
            PlannedRoute(coordinates: [from, bend, to], name: "Test road")
        }
        planner.plan(from: start, to: end)
        try await finish(planner)
        XCTAssertEqual(planner.waypoints.count, 3)
        XCTAssertEqual(planner.waypoints[1].coordinate.latitude, bend.latitude)
        XCTAssertEqual(planner.waypoints[1].coordinate.longitude, bend.longitude)
        XCTAssertEqual(planner.name, "Test road")
        XCTAssertNil(planner.error)
    }

    func testFailureDoesNotLeaveAPlayableStraightLine() async throws {
        let planner = RoutePlanner { _, _ in throw NSError(domain: "Offline", code: 1) }
        planner.plan(from: start, to: end)
        try await finish(planner)
        XCTAssertTrue(planner.waypoints.isEmpty)
        XCTAssertNotNil(planner.error)
        planner.clear()
        XCTAssertNil(planner.error)
        XCTAssertFalse(planner.isLoading)
    }

    func testLateResponseCannotReplaceNewerDestination() async throws {
        var pending: CheckedContinuation<PlannedRoute, Error>?
        let planner = RoutePlanner { from, to in
            if to.latitude == 41 {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return PlannedRoute(coordinates: [from, to], name: "New route")
        }
        planner.plan(from: start, to: end)
        for _ in 0..<200 {
            if pending != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let oldRequest = try XCTUnwrap(pending)
        let replacement = RoutePlace(title: "New destination", coordinate: .init(latitude: 42, longitude: -73))
        planner.plan(from: start, to: replacement)
        try await finish(planner)
        oldRequest.resume(returning: PlannedRoute(coordinates: [start.coordinate, end.coordinate], name: "Old route"))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(planner.name, "New route")
        XCTAssertEqual(planner.waypoints.last?.coordinate.latitude, 42)
    }

    func testMissingOrIdenticalEndpointsDoNotRequestDirections() {
        let planner = RoutePlanner { _, _ in
            XCTFail("Incomplete routes must not request directions")
            return PlannedRoute(coordinates: [], name: "")
        }
        planner.plan(from: start, to: nil)
        XCTAssertFalse(planner.isLoading)
        planner.plan(from: start, to: start)
        XCTAssertFalse(planner.isLoading)
        XCTAssertNotNil(planner.error)
        XCTAssertTrue(planner.waypoints.isEmpty)
    }
}
