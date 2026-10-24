import AppKit
import MapKit
import SwiftUI
import XCTest
@testable import LockShift

final class MapGestureTests: XCTestCase {
    @MainActor func testWindowlessGesturesUseTheKeyWindowOnly() {
        let mapWindow = NSWindow()
        let otherWindow = NSWindow()
        XCTAssertTrue(DestinationMapView.isZoomEventWindow(nil, mapWindow: mapWindow, keyWindow: mapWindow))
        XCTAssertFalse(DestinationMapView.isZoomEventWindow(nil, mapWindow: mapWindow, keyWindow: otherWindow))
        XCTAssertFalse(DestinationMapView.isZoomEventWindow(otherWindow, mapWindow: mapWindow, keyWindow: mapWindow))
        XCTAssertTrue(DestinationMapView.isZoomEventWindow(mapWindow, mapWindow: mapWindow, keyWindow: otherWindow))
    }

    @MainActor func testMapTakesTheClickThatActivatesTheWindow() {
        // Otherwise the first click is spent activating the window and placing a
        // pin needs a second one.
        XCTAssertTrue(DestinationMapView(frame: .zero).acceptsFirstMouse(for: nil))
    }

    @MainActor func testFocusCentersTheSelectionWithoutChangingZoom() {
        let wide = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 110, longitudeDelta: 160)
        )
        let picked = CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945)
        let panned = MapView.Coordinator.region(wide, centeredOn: picked)
        XCTAssertEqual(panned.center.latitude, picked.latitude, accuracy: 0.0001)
        XCTAssertEqual(panned.center.longitude, picked.longitude, accuracy: 0.0001)
        XCTAssertEqual(panned.span.latitudeDelta, wide.span.latitudeDelta, accuracy: 0.0001,
                       "Picking a destination must not zoom the map")
        XCTAssertEqual(panned.span.longitudeDelta, wide.span.longitudeDelta, accuracy: 0.0001)
    }

    @MainActor func testZoomHitTestingDoesNotMirrorMapAndOverlay() throws {
        // A flipped content view matches SwiftUI. Keep an asymmetric overlay so
        // confusing local and parent coordinates cannot accidentally pass.
        final class FlippedView: NSView { override var isFlipped: Bool { true } }
        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 1000, height: 680))
        let window = NSWindow(contentRect: content.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = content
        let map = DestinationMapView(frame: content.bounds)
        content.addSubview(map)
        let overlay = NSButton(frame: NSRect(x: 400, y: 20, width: 300, height: 100))
        content.addSubview(overlay)
        let overButton = overlay.convert(NSPoint(x: 50, y: 50), to: nil)
        let overMap = content.convert(NSPoint(x: 450, y: 610), to: nil)
        XCTAssertFalse(map.acceptsZoom(atWindowPoint: overButton), "Overlay controls must keep their gestures")
        XCTAssertTrue(map.acceptsZoom(atWindowPoint: overMap), "The map below the overlay must receive zoom gestures")
    }
}
