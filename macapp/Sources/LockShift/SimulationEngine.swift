import Combine
import CoreLocation
import Foundation

/// A point the user dropped on the map.
struct Waypoint: Identifiable, Hashable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D

    static func == (l: Waypoint, r: Waypoint) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum PlaybackState: Equatable {
    case idle
    case playing
    case paused
}

/// Drives simulated movement along the route at a chosen speed and pushes each
/// interpolated coordinate to the device through the `Sidecar`.
///
/// This is the part that makes us Lockito-equivalent: we own the interpolation,
/// so speed, pause and loop are all under our control rather than
/// relying on the device's own GPX timing.
@MainActor
final class SimulationEngine: ObservableObject {
    @Published var waypoints: [Waypoint] = []
    @Published var speedKmh: Double = 50      // target ground speed
    @Published var loop: Bool = false

    @Published private(set) var playback: PlaybackState = .idle
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var progress: Double = 0 // 0...1 along the route

    private let sidecar: Sidecar
    private var timer: Timer?
    private var travelled: Double = 0          // metres along the route
    private let now: () -> TimeInterval
    private var lastUpdate: TimeInterval = 0
    private var timerGeneration = UUID()
    private let updateInterval: TimeInterval = 0.1 // Fixed 10 Hz device updates.

    init(sidecar: Sidecar, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.sidecar = sidecar
        self.now = now
    }

    var coordinates: [CLLocationCoordinate2D] { waypoints.map(\.coordinate) }
    var totalDistance: Double { Geo.pathLength(coordinates) }

    // MARK: - Editing

    func addWaypoint(_ c: CLLocationCoordinate2D) {
        waypoints.append(Waypoint(coordinate: c))
    }

    func clearRoute() {
        stop()
        waypoints.removeAll()
        currentCoordinate = nil
        progress = 0
    }

    // MARK: - Teleport (single static location)

    func teleport(to c: CLLocationCoordinate2D) {
        guard sidecar.state.isReady, !sidecar.isRestoring else { return }
        currentCoordinate = c
        sidecar.setLocation(c.latitude, c.longitude)
    }

    // MARK: - Route playback

    func play() {
        guard sidecar.state.isReady, !sidecar.isRestoring else { return }
        guard coordinates.count >= 2 else {
            // A single point behaves like teleport.
            if let only = coordinates.first { teleport(to: only) }
            return
        }
        guard playback != .playing, totalDistance > 0 else { return }
        if playback == .idle { travelled = 0 }
        lastUpdate = now()
        playback = .playing
        emitCurrent(total: totalDistance)
        scheduleTimer()
    }

    func pause() {
        guard playback == .playing else { return }
        step()
        guard playback == .playing else { return }
        playback = .paused
        timerGeneration = UUID()
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        playback = .idle
        travelled = 0
        progress = 0
        timerGeneration = UUID()
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timerGeneration = UUID()
        let generation = timerGeneration
        let t = Timer(timeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.timerGeneration == generation else { return }
                self.step()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func step() {
        guard playback == .playing else { return }
        guard sidecar.state.isReady, !sidecar.isRestoring else { stop(); return }
        let timestamp = now()
        let elapsed = max(0, timestamp - lastUpdate)
        lastUpdate = timestamp
        guard elapsed > 0 else { return }
        let total = totalDistance
        guard total > 0 else { stop(); return }

        let speedMps = speedKmh * 1000 / 3600
        travelled += speedMps * elapsed

        if travelled >= total {
            if loop {
                travelled = travelled.truncatingRemainder(dividingBy: total)
            } else {
                travelled = total
                emitCurrent(total: total)
                stop()
                return
            }
        }
        emitCurrent(total: total)
    }

    private func emitCurrent(total: Double) {
        guard let c = Geo.point(along: coordinates, at: travelled) else { return }
        currentCoordinate = c
        progress = total == 0 ? 0 : min(1, travelled / total)
        sidecar.setLocation(c.latitude, c.longitude)
    }

    // MARK: - Readouts

    var speedMph: Double {
        get { speedKmh / 1.609344 }
        set { speedKmh = newValue * 1.609344 }
    }

    var estimatedDurationSeconds: Double {
        let speedMps = speedKmh * 1000 / 3600
        return speedMps > 0 ? totalDistance / speedMps : 0
    }
}
