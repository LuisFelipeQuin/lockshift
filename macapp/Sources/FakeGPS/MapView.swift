import AppKit
import CoreLocation
import MapKit
import SwiftUI

/// A MapKit map that lets the user click to drop route waypoints, renders the
/// route polyline, and shows a live marker at the simulated position.
struct MapView: NSViewRepresentable {
    var waypoints: [Waypoint]
    var currentCoordinate: CLLocationCoordinate2D?
    var selectedCoordinate: CLLocationCoordinate2D?
    var controller: MapController
    /// Called with the map coordinate the user clicked.
    var onTap: (CLLocationCoordinate2D) -> Void
    var onPan: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsZoomControls = true
        map.showsCompass = true
        map.showsPitchControl = false
        map.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = true
        map.isPitchEnabled = true
        // Single-click drops a waypoint; require exactly one click so it doesn't
        // swallow the map's own double-click-to-zoom or drag-to-pan.
        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        click.numberOfClicksRequired = 1
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
        context.coordinator.sync(waypoints: waypoints, current: currentCoordinate)
        context.coordinator.syncSelection(selectedCoordinate)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        weak var mapView: MKMapView?
        private var routeOverlay: MKPolyline?
        private let currentAnnotation = MKPointAnnotation()
        private var hasCurrent = false
        private let selectionAnnotation = MKPointAnnotation()
        private var previousWaypoints: [UUID] = []
        private var programmaticMove = false

        init(_ parent: MapView) {
            self.parent = parent
            currentAnnotation.title = "iPhone location"
        }

        /// Expose map commands to SwiftUI through the shared MapController.
        func bindController() {
            let controller = parent.controller
            controller.recenter = { [weak self] coord, meters in
                guard let map = self?.mapView else { return }
                self?.programmaticMove = true
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
            } else { map.removeAnnotation(selectionAnnotation) }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !programmaticMove, let event = NSApp.currentEvent,
               [.leftMouseDragged, .rightMouseDragged, .scrollWheel, .magnify, .rotate].contains(event.type) { parent.onPan() }
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { programmaticMove = false }

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
                view.canShowCallout = true
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
                view.setAccessibilityLabel("iPhone location")
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
