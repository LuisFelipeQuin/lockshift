import Combine
import MapKit

struct PlannedRoute {
    let coordinates: [CLLocationCoordinate2D]
    let name: String
}

@MainActor
final class RoutePlanner: ObservableObject {
    typealias Fetch = (CLLocationCoordinate2D, CLLocationCoordinate2D) async throws -> PlannedRoute
    @Published private(set) var waypoints: [Waypoint] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var name = ""
    private let fetch: Fetch
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(fetch: @escaping Fetch = RoutePlanner.drivingRoute) {
        self.fetch = fetch
    }

    func clear() {
        generation = UUID()
        task?.cancel()
        task = nil
        waypoints = []
        name = ""
        error = nil
        isLoading = false
    }

    func plan(from start: RoutePlace?, to end: RoutePlace?) {
        clear()
        guard let start, let end else { return }
        guard Geo.distance(start.coordinate, end.coordinate) >= 1 else {
            error = "Choose a destination different from your starting point."
            return
        }
        isLoading = true
        let requestID = generation
        let fetch = self.fetch
        task = Task { [weak self] in
            do {
                let route = try await fetch(start.coordinate, end.coordinate)
                guard let self, self.generation == requestID, !Task.isCancelled else { return }
                guard route.coordinates.count >= 2, Geo.pathLength(route.coordinates) >= 1 else {
                    self.error = "No driving route was found between these addresses."
                    self.isLoading = false
                    return
                }
                self.waypoints = route.coordinates.map { Waypoint(coordinate: $0) }
                self.name = route.name
                self.isLoading = false
            } catch {
                guard let self, self.generation == requestID, !Task.isCancelled else { return }
                self.error = "Couldn’t calculate a driving route. Check your internet connection or try different addresses."
                self.isLoading = false
            }
        }
    }

    nonisolated static func drivingRoute(from start: CLLocationCoordinate2D,
                                        to end: CLLocationCoordinate2D) async throws -> PlannedRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        return try await withTaskCancellationHandler {
            let response = try await directions.calculate()
            guard let route = response.routes.first else {
                throw NSError(domain: "RoutePlanner", code: 1)
            }
            var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: route.polyline.pointCount)
            route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
            return PlannedRoute(coordinates: coordinates, name: route.name)
        } onCancel: {
            directions.cancel()
        }
    }
}
