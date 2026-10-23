import CoreLocation
import Foundation
import MapKit

/// Bridge that lets SwiftUI views drive the underlying `MKMapView`
/// (recenter, zoom). The `MapView` coordinator wires these closures up. Not
/// actor-isolated: the closures are assigned by the (non-isolated) map
/// coordinator and only ever invoked on the main thread.
final class MapController: ObservableObject {
    var recenter: ((CLLocationCoordinate2D, CLLocationDistance) -> Void)?
    var panTo: ((CLLocationCoordinate2D) -> Void)?
    var zoomBy: ((Double) -> Void)?
    var currentCenter: (() -> CLLocationCoordinate2D?)?

    func center(on coord: CLLocationCoordinate2D, meters: CLLocationDistance = 1_500) {
        recenter?(coord, meters)
    }

    /// Brings a coordinate to the middle of the map at the zoom the user has
    /// already chosen. Unlike `center(on:meters:)` this never zooms, so picking
    /// a destination cannot yank a wide overview down to street level.
    func focus(on coord: CLLocationCoordinate2D) {
        panTo?(coord)
    }

    func zoomIn() { zoomBy?(0.5) }
    func zoomOut() { zoomBy?(2.0) }
}

/// Address / place autocomplete backed by `MKLocalSearchCompleter`.
///
/// The completer is the cheap, as-you-type half of MapKit search: it streams
/// suggestion rows for a query fragment without performing a full lookup. Only
/// the row the user actually picks is resolved into a placemark, which keeps us
/// well clear of the throttling a per-keystroke `MKLocalSearch` runs into.
@MainActor
final class PlaceSearch: NSObject, ObservableObject {
    @Published var query: String = ""
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private var task: Task<Void, Never>?

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
    }

    /// Feeds the current query to the completer, biasing results around the
    /// visible map region when we have one.
    func update(near center: CLLocationCoordinate2D?) {
        let fragment = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fragment.count >= 2 else {
            completer.cancel()
            suggestions = []
            return
        }
        if let center {
            completer.region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
            )
        }
        completer.queryFragment = fragment
    }

    /// Turns a suggestion row into a concrete map item (the only network-heavy
    /// step). Returns `nil` if the lookup fails or is superseded.
    func resolve(_ suggestion: MKLocalSearchCompletion) async -> MKMapItem? {
        task?.cancel()
        isSearching = true
        defer { isSearching = false }
        do {
            let response = try await MKLocalSearch(request: .init(completion: suggestion)).start()
            return response.mapItems.first
        } catch {
            return nil
        }
    }

    /// Enter key: resolve the top suggestion, or fall back to a plain search of
    /// whatever was typed when the completer returned nothing.
    func submit(near center: CLLocationCoordinate2D?) async -> MKMapItem? {
        if let first = suggestions.first { return await resolve(first) }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return nil }
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        if let center {
            request.region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
            )
        }
        return try? await MKLocalSearch(request: request).start().mapItems.first
    }

    func clear() {
        task?.cancel()
        completer.cancel()
        query = ""
        suggestions = []
    }
}

extension PlaceSearch: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }
}

extension MKLocalSearchCompletion {
    var displayTitle: String { title }
    var displaySubtitle: String { subtitle }
}

extension MKMapItem {
    var displayTitle: String { name ?? "Unknown" }
    var displaySubtitle: String {
        let p = placemark
        return [p.thoroughfare, p.locality, p.administrativeArea, p.country]
            .compactMap { $0 }.joined(separator: ", ")
    }
    var coordinate: CLLocationCoordinate2D { placemark.coordinate }
}
