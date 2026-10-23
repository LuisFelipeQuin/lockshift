import AppKit
import CoreLocation
import MapKit
import SwiftUI

/// A MapKit map that lets the user click to drop route waypoints, renders the
/// route polyline, and shows a live marker at the simulated position.
struct MapView: NSViewRepresentable {
    var waypoints: [Waypoint]
    var currentCoordinate: CLLocationCoordinate2D?
    var locationTitle: String
    var locationAccessReady: Bool
    var selectedCoordinate: CLLocationCoordinate2D?
    var canMoveToSelection: Bool
    var onMoveToSelection: () -> Void
    var onDismissSelection: () -> Void
    var controller: MapController
    /// Called with the map coordinate the user clicked.
    var onTap: (CLLocationCoordinate2D) -> Void
    var onPan: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MKMapView {
        let map = DestinationMapView()
        map.onLayout = { [weak coordinator = context.coordinator] in coordinator?.positionDestinationCard() }
        map.onManualZoom = { [weak coordinator = context.coordinator] in coordinator?.parent.onPan() }
        map.delegate = context.coordinator
        map.showsZoomControls = true
        map.showsCompass = true
        map.showsUserTrackingButton = true
        map.showsPitchControl = false
        map.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = true
        map.isPitchEnabled = true
        // Single-click drops a waypoint; require exactly one click so it doesn't
        // swallow the map's own double-click-to-zoom or drag-to-pan.
        let click = MapSelectionClickRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        click.numberOfClicksRequired = 1
        click.delegate = context.coordinator
        click.delaysPrimaryMouseButtonEvents = false
        map.addGestureRecognizer(click)
        context.coordinator.mapView = map
        context.coordinator.bindController()
        // Neutral overview until a simulated location or explicit selection is available.
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 110, longitudeDelta: 160)
            ),
            animated: false
        )
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if map.showsUserLocation != locationAccessReady {
            map.showsUserLocation = locationAccessReady
        }
        context.coordinator.sync(waypoints: waypoints, current: currentCoordinate)
        context.coordinator.syncSelection(selectedCoordinate)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, NSGestureRecognizerDelegate {
        var parent: MapView
        weak var mapView: MKMapView?
        private var routeOverlay: MKPolyline?
        private let currentAnnotation = MKPointAnnotation()
        private var hasCurrent = false
        private let selectionAnnotation = MKPointAnnotation()
        private var destinationCard: NSHostingView<DestinationCard>?
        private var previousWaypoints: [UUID] = []

        init(_ parent: MapView) {
            self.parent = parent
            currentAnnotation.title = parent.locationTitle
        }

        /// Expose map commands to SwiftUI through the shared MapController.
        func bindController() {
            let controller = parent.controller
            controller.recenter = { [weak self] coord, meters in
                guard let map = self?.mapView else { return }
                // Explicit destinations leave native location tracking.
                map.setUserTrackingMode(.none, animated: false)
                map.setRegion(
                    MKCoordinateRegion(center: coord, latitudinalMeters: meters, longitudinalMeters: meters),
                    animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                )
            }
            controller.zoomBy = { [weak self] factor in
                guard let map = self?.mapView else { return }
                var region = map.region
                region.span = MKCoordinateSpan(
                    latitudeDelta: min(120, max(0.0008, region.span.latitudeDelta * factor)),
                    longitudeDelta: min(120, max(0.0008, region.span.longitudeDelta * factor))
                )
                map.setRegion(region, animated: true)
            }
            controller.currentCenter = { [weak self] in self?.mapView?.region.center }
        }

        @objc func handleClick(_ gr: NSClickGestureRecognizer) {
            guard let map = mapView else { return }
            let point = gr.location(in: map)
            let coord = map.convert(point, toCoordinateFrom: map)
            parent.onTap(coord)
        }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
            // Pin placement only owns primary-button clicks. Trackpad gesture
            // streams must go straight to MapKit, even during a camera animation.
            if [.beginGesture, .magnify, .rotate, .scrollWheel].contains(event.type) {
                parent.onPan()
                return false
            }
            guard event.type == .leftMouseDown, let map = mapView else { return false }
            let point = map.convert(event.locationInWindow, from: nil)
            var hit = map.hitTest(map.convert(point, to: map.superview))
            while let view = hit, view !== map {
                if view is NSControl || view === destinationCard { return false }
                hit = view.superview
            }
            return true
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            if mode != .none {
                // Let MapKit own the camera while its native locate mode is active.
                parent.onPan()
            }
        }

        func sync(waypoints: [Waypoint], current: CLLocationCoordinate2D?) {
            guard let map = mapView else { return }

            // Rebuild route geometry only when the stops change, not every GPS tick.
            if previousWaypoints != waypoints.map(\.id) {
                previousWaypoints = waypoints.map(\.id)
                let existing = map.annotations.compactMap { $0 as? WaypointAnnotation }
                map.removeAnnotations(existing)
                for (i, wp) in waypoints.enumerated() {
                    let a = WaypointAnnotation()
                    a.coordinate = wp.coordinate
                    a.title = "\(i + 1)"
                    map.addAnnotation(a)
                }

                // Route polyline.
                if let old = routeOverlay { map.removeOverlay(old) }
                if waypoints.count >= 2 {
                    let line = MKPolyline(coordinates: waypoints.map(\.coordinate), count: waypoints.count)
                    map.addOverlay(line)
                    routeOverlay = line
                } else {
                    routeOverlay = nil
                }

            }

            // Live simulated-position marker.
            if let current {
                currentAnnotation.title = parent.locationTitle
                map.view(for: currentAnnotation)?.setAccessibilityLabel(parent.locationTitle)
                currentAnnotation.coordinate = current
                if !hasCurrent {
                    map.addAnnotation(currentAnnotation)
                    hasCurrent = true
                }
            } else if hasCurrent {
                map.removeAnnotation(currentAnnotation)
                hasCurrent = false
            }
        }

        func syncSelection(_ selected: CLLocationCoordinate2D?) {
            guard let map = mapView else { return }
            if let selected {
                selectionAnnotation.title = "Selected destination"
                selectionAnnotation.coordinate = selected
                if !map.annotations.contains(where: { $0 === selectionAnnotation }) { map.addAnnotation(selectionAnnotation) }
                let content = DestinationCard(coordinate: selected, canMove: parent.canMoveToSelection,
                                              onMove: parent.onMoveToSelection, onDismiss: parent.onDismissSelection)
                if let destinationCard {
                    destinationCard.rootView = content
                } else {
                    let card = NSHostingView(rootView: content)
                    map.addSubview(card)
                    destinationCard = card
                }
                positionDestinationCard()
            } else {
                map.removeAnnotation(selectionAnnotation)
                destinationCard?.removeFromSuperview()
                destinationCard = nil
            }
        }

        // Keep the card attached while panning, zooming, or resizing the window.
        func positionDestinationCard() {
            guard let map = mapView, let card = destinationCard else { return }
            let point = map.convert(selectionAnnotation.coordinate, toPointTo: map)
            let visible = map.bounds.insetBy(dx: 16, dy: 16)
            card.isHidden = !visible.contains(point) || point.x < 328
            let size = NSSize(width: 292, height: 252)
            let right = point.x + 28
            let x = right + size.width <= visible.maxX ? right : point.x - size.width - 28
            card.frame = NSRect(x: max(328, min(x, visible.maxX - size.width)),
                                y: max(visible.minY, min(point.y - size.height / 2, visible.maxY - size.height)),
                                width: size.width, height: size.height)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            positionDestinationCard()
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // User input takes precedence even if it interrupts a recenter animation.
            if let event = NSApp.currentEvent,
               [.leftMouseDragged, .rightMouseDragged, .scrollWheel, .magnify, .rotate].contains(event.type) {
                parent.onPan()
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .systemBlue
                r.lineWidth = 4
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        /// A centered blue location dot with a white edge and soft halo.
        /// This is a custom annotation, so it can also represent a simulated position.
        private static let locationDot = NSImage(size: NSSize(width: 44, height: 44), flipped: false) { _ in
            NSColor.systemBlue.withAlphaComponent(0.14).setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 40, height: 40)).fill()
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 11, y: 11, width: 22, height: 22)).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: NSRect(x: 14, y: 14, width: 16, height: 16)).fill()
            return true
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation === selectionAnnotation {
                let id = "selection"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.markerTintColor = .systemOrange
                view.glyphImage = NSImage(systemSymbolName: "mappin", accessibilityDescription: nil)
                view.displayPriority = .required
                view.canShowCallout = false
                view.titleVisibility = .hidden
                return view
            }
            if annotation === currentAnnotation {
                let id = "current"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.image = Self.locationDot
                view.centerOffset = .zero
                view.canShowCallout = true
                view.displayPriority = .required
                view.collisionMode = .circle
                view.setAccessibilityLabel(parent.locationTitle)
                return view
            }

            if annotation is WaypointAnnotation {
                let id = "wp"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.markerTintColor = .systemBlue
                v.glyphText = (annotation as? WaypointAnnotation)?.title ?? ""
                return v
            }
            return nil
        }
    }
}

/// Distinguishes user-placed waypoints from the live position marker.
final class WaypointAnnotation: MKPointAnnotation {}

final class DestinationMapView: MKMapView {
    var onLayout: (() -> Void)?
    var onManualZoom: (() -> Void)?
    private var zoomMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let zoomMonitor {
            NSEvent.removeMonitor(zoomMonitor)
            self.zoomMonitor = nil
        }
        guard window != nil else { return }
        // MapKit's internal subviews can consume scroll events before responder
        // overrides run. Scope this monitor to events hit-tested to this map.
        zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
            guard let self, self.isZoomEnabled, let window = self.window,
                  Self.isZoomEventWindow(event.window, mapWindow: window, keyWindow: NSApp.keyWindow) else { return event }
            // Gesture events may have no associated window yet. In that case,
            // their locationInWindow is not a coordinate in this map's window.
            let point = event.window == nil ? window.mouseLocationOutsideOfEventStream : event.locationInWindow
            guard self.acceptsZoom(atWindowPoint: point) else { return event }

            let factor: Double
            if event.type == .magnify {
                factor = max(0.01, 1 + Double(event.magnification))
            } else {
                guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
                let sensitivity = event.hasPreciseScrollingDeltas ? 0.008 : 0.12
                factor = exp(max(-1, min(1, Double(event.scrollingDeltaY) * sensitivity)))
            }
            guard factor != 1 else { return nil }
            self.onManualZoom?()
            self.setUserTrackingMode(.none, animated: false)
            let camera = self.camera.copy() as! MKMapCamera
            camera.centerCoordinateDistance = min(40_000_000, max(20, camera.centerCoordinateDistance / factor))
            self.setCamera(camera, animated: false)
            // Consume once so MapKit cannot apply a second zoom or scroll-pan.
            return nil
        }
    }

    static func isZoomEventWindow(_ eventWindow: NSWindow?, mapWindow: NSWindow, keyWindow: NSWindow?) -> Bool {
        (eventWindow ?? keyWindow) === mapWindow
    }

    func acceptsZoom(atWindowPoint point: NSPoint) -> Bool {
        guard let content = window?.contentView else { return false }
        // NSView.hitTest takes a point in its SUPERview, not its own bounds.
        // SwiftUI's content view is flipped, so converting to it mirrors Y.
        let hitPoint = content.superview?.convert(point, from: nil) ?? point
        var hit = content.hitTest(hitPoint)
        while let view = hit, view !== self {
            if view is NSControl || view is NSHostingView<DestinationCard> { return false }
            hit = view.superview
        }
        return hit === self
    }

    deinit {
        if let zoomMonitor { NSEvent.removeMonitor(zoomMonitor) }
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// Dropping a pin must never prevent MapKit's native zoom, pan, or rotation.
private final class MapSelectionClickRecognizer: NSClickGestureRecognizer {
    override func canPrevent(_ preventedGestureRecognizer: NSGestureRecognizer) -> Bool { false }
}
