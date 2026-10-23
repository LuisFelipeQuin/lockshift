import MapKit
import XCTest
@testable import FakeGPS

final class RouteMapTests: XCTestCase {
    func testCameraBoundsIncludeBothEndpointsAndSinglePointHasUsefulZoom() throws {
        let start = CLLocationCoordinate2D(latitude: 40.7, longitude: -74)
        let end = CLLocationCoordinate2D(latitude: 40.8, longitude: -73.9)
        let single = try XCTUnwrap(MapView.Coordinator.routeBounds([start]))
        XCTAssertGreaterThan(single.width, 0)
        XCTAssertGreaterThan(single.height, 0)
        XCTAssertTrue(single.contains(MKMapPoint(start)))
        let both = try XCTUnwrap(MapView.Coordinator.routeBounds([start, end]))
        for coordinate in [start, end] {
            let point = MKMapPoint(coordinate)
            XCTAssertGreaterThanOrEqual(point.x, both.minX)
            XCTAssertLessThanOrEqual(point.x, both.maxX)
            XCTAssertGreaterThanOrEqual(point.y, both.minY)
            XCTAssertLessThanOrEqual(point.y, both.maxY)
        }
        XCTAssertNil(MapView.Coordinator.routeBounds([]))
    }

    func testEndpointRolesRemainCorrectWhenOnlyOneAddressIsSelected() throws {
        let start = RoutePlace(title: "Start", coordinate: .init(latitude: 40.7, longitude: -74))
        let end = RoutePlace(title: "Finish", coordinate: .init(latitude: 40.8, longitude: -73.9))
        let startOnly = MapView.Coordinator.endpointAnnotations([start, nil])
        XCTAssertEqual(startOnly.count, 1)
        XCTAssertTrue(try XCTUnwrap(startOnly.first).isStart)
        let finishOnly = MapView.Coordinator.endpointAnnotations([nil, end])
        XCTAssertEqual(finishOnly.count, 1)
        XCTAssertFalse(try XCTUnwrap(finishOnly.first).isStart)
        XCTAssertEqual(finishOnly.first?.title, "Destination")
        XCTAssertEqual(finishOnly.first?.coordinate.latitude, end.latitude)
        XCTAssertEqual(MapView.Coordinator.endpointAnnotations([start, end]).count, 2)
        XCTAssertTrue(MapView.Coordinator.endpointAnnotations([nil, nil]).isEmpty)
    }
}
