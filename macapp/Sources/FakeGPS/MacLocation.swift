import Combine
import CoreLocation
import Foundation

/// One location fix per USB connection, used only as a map placeholder.
/// It never sends a simulation command to the iPhone.
@MainActor
final class MacLocation: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var isLocating = false
    @Published private(set) var message = ""

    private var manager: CLLocationManager?
    private var timeout: Task<Void, Never>?
    private var requestedFix = false

    func request() {
        cancel()
        isLocating = true
        message = "Finding this Mac’s location…"
        let manager = CLLocationManager()
        self.manager = manager
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        updateAuthorization(manager)
    }

    func cancel() {
        timeout?.cancel()
        timeout = nil
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        requestedFix = false
        location = nil
        isLocating = false
        message = ""
    }

    private func updateAuthorization(_ manager: CLLocationManager) {
        guard self.manager === manager, isLocating else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            message = "Allow location access to find this Mac."
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requestedFix else { return }
            requestedFix = true
            message = "Finding this Mac’s location…"
            manager.requestLocation()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard let self, self.isLocating else { return }
                self.fail("Couldn’t find this Mac. Check Location Services and try again.")
            }
        case .denied, .restricted:
            fail("Allow iOS Fake GPS in System Settings → Privacy & Security → Location Services.")
        @unknown default:
            fail("This Mac’s location is unavailable.")
        }
    }

    private func fail(_ message: String) {
        timeout?.cancel()
        manager?.stopUpdatingLocation()
        isLocating = false
        self.message = message
    }
}

extension MacLocation: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.updateAuthorization(manager) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.manager === manager, self.isLocating else { return }
            // Do not center on a cached fix from a previous trip or connection.
            guard let fix = locations.last(where: {
                $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy.isFinite
                    && CLLocationCoordinate2DIsValid($0.coordinate)
                    && abs($0.timestamp.timeIntervalSinceNow) < 60
            }) else {
                self.fail("No recent location available. Try again.")
                return
            }
            self.timeout?.cancel()
            manager.stopUpdatingLocation()
            self.location = fix
            self.isLocating = false
            self.message = "iPhone location"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.manager === manager, self.isLocating else { return }
            if (error as? CLError)?.code == .denied {
                self.fail("Allow iOS Fake GPS in System Settings → Privacy & Security → Location Services.")
            } else {
                self.fail("Couldn’t find this Mac’s location. Try again.")
            }
        }
    }
}
