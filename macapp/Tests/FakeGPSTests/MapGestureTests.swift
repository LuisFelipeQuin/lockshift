import AppKit
import MapKit
import SwiftUI
import XCTest
@testable import FakeGPS

final class MapGestureTests: XCTestCase {
    @MainActor func testWindowlessGesturesUseTheKeyWindowOnly() {
        let mapWindow = NSWindow()
        let otherWindow = NSWindow()
        XCTAssertTrue(DestinationMapView.isZoomEventWindow(nil, mapWindow: mapWindow, keyWindow: mapWindow))
        XCTAssertFalse(DestinationMapView.isZoomEventWindow(nil, mapWindow: mapWindow, keyWindow: otherWindow))
        XCTAssertFalse(DestinationMapView.isZoomEventWindow(otherWindow, mapWindow: mapWindow, keyWindow: mapWindow))
        XCTAssertTrue(DestinationMapView.isZoomEventWindow(mapWindow, mapWindow: mapWindow, keyWindow: otherWindow))
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
