import CoreLocation
import MapKit
import SwiftUI

enum EditMode: String, CaseIterable, Identifiable {
    case explore = "My iPhone"
    case teleport = "Move location"
    case route = "Build a route"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var sidecar: Sidecar
    @EnvironmentObject var engine: SimulationEngine
    @EnvironmentObject var tunnel: TunnelManager
    @EnvironmentObject var devices: DeviceWatcher
    @StateObject private var mapController = MapController()
    @StateObject private var search = PlaceSearch()
    @StateObject private var macLocation = MacLocation()
    @State private var mode: EditMode = .explore
    @State private var selection: CLLocationCoordinate2D?
    @State private var connectionError: String?
    @State private var restoreError: String?
    @State private var connectionAttempt = 0
    @State private var following = true
    @State private var advanced = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 300)
            Divider()
            ZStack(alignment: .top) {
                MapView(waypoints: engine.waypoints,
                        currentCoordinate: displayedCoordinate,
                        selectedCoordinate: selection,
                        controller: mapController, onTap: handleTap,
                        onPan: { following = false })
                VStack(spacing: 12) {
                    deviceCard
                    if devices.hasDevice && mode != .explore {
                        Label(mode == .teleport ? "Choose a place, then click Move here" : "Click the map to add stops", systemImage: "hand.tap")
                            .font(.callout).padding(.horizontal, 16).padding(.vertical, 9)
                            .background(.regularMaterial, in: Capsule())
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        if devices.hasDevice, mode == .teleport, let selection {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Selected destination").font(.headline)
                                Text(coordinateText(selection)).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Button("Move here") {
                                    engine.stop()
                                    engine.teleport(to: selection)
                                    self.selection = nil
                                    following = true
                                    centerOnDisplayedLocation()
                                }.buttonStyle(.borderedProminent).disabled(!canSimulate)
                            }
                            .padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                        Spacer()
                    }
                }.padding(20)
            }
        }
        .frame(minWidth: 940, idealWidth: 1180, minHeight: 650, idealHeight: 760)
        .task(id: "\(devices.connectedUDID ?? "none")-\(connectionAttempt)") {
            await connectAutomatically()
        }
        .onChange(of: displayedCoordinate.map { [$0.latitude, $0.longitude] }) { _, _ in
            centerOnDisplayedLocation()
        }
        .onChange(of: devices.hasDevice, initial: true) { _, connected in
            if connected {
                following = true
                macLocation.request()
                centerOnDisplayedLocation()
            } else {
                macLocation.cancel()
                engine.clearRoute()
                sidecar.stop()
                selection = nil
                mode = .explore
            }
        }
        .onChange(of: mode) { _, _ in search.clear() }
        .onChange(of: sidecar.state.isReady) { _, ready in
            if !ready && !sidecar.isRestoring {
                engine.clearRoute()
                selection = nil
                mode = .explore
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "location.circle.fill").font(.title).foregroundStyle(.blue)
                Text("iOS Fake GPS").font(.title3.weight(.semibold))
            }.padding(22)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sidebarSearch.disabled(!canSimulate)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EXPLORE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
                        ForEach(EditMode.allCases) { item in
                            Button { withAnimation(.easeInOut(duration: 0.2)) { selection = nil; mode = item } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: icon(item)).frame(width: 20)
                                    Text(item.rawValue)
                                    Spacer()
                                    if mode == item { Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                                }
                                .font(.system(size: 14, weight: mode == item ? .semibold : .regular))
                                .padding(12)
                                .background(mode == item ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(mode == item ? Color.accentColor : .primary)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .disabled(item != .explore && !canSimulate)
                                .opacity(item != .explore && !canSimulate ? 0.4 : 1)
                        }
                    }
                    if mode == .route { routeControls }
                    if let restoreError { Text(restoreError).font(.caption).foregroundStyle(.orange) }
                    if let error = connectionError, devices.hasDevice {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.caption).foregroundStyle(.orange)
                            Button("Retry connection") { connectionAttempt += 1 }
                        }
                    } else if let error = sidecar.lastError, canSimulate {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle().fill(sidecar.state.isReady ? .green : .secondary).frame(width: 7, height: 7)
                    Text(connectionStatus).font(.caption)
                    Spacer()
                }
                if sidecar.state.isReady {
                    Button(sidecar.isRestoring ? "Restoring location…" : "Restore real location") {
                        Task { await restoreLocation() }
                    }.disabled(sidecar.isRestoring)
                }
            }.padding(20)
        }
        .background(.regularMaterial)
    }

    private var deviceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: devices.hasDevice ? "iphone" : "iphone.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(devices.hasDevice ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(devices.hasDevice ? "iPhone connected" : "No iPhone connected")
                    .font(.headline)
                if !devices.hasDevice {
                    Text("Connect your iPhone with a USB cable.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if displayedCoordinate != nil {
                    Text("iPhone location")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        if macLocation.isLocating { ProgressView().controlSize(.small) }
                        Text(macLocation.message).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !macLocation.isLocating {
                        Button("Try again") { macLocation.request() }.font(.caption)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func restoreLocation() async {
        guard canSimulate else { return }
        engine.stop()
        selection = nil
        restoreError = nil
        if await sidecar.restoreLocation() {
            engine.clearRoute()
            mode = .explore
            following = true
            if devices.hasDevice { macLocation.request() }
        } else {
            restoreError = sidecar.lastError ?? "Couldn’t restore location. Try again."
        }
    }

    private var canSimulate: Bool { devices.hasDevice && sidecar.state.isReady && !sidecar.isRestoring }

    private var connectionStatus: String {
        if !devices.hasDevice { return "Connect your iPhone to get started" }
        if sidecar.isRestoring { return "Restoring location…" }
        if canSimulate, case let .ready(device) = sidecar.state {
            return device.usbConnectionDescription
        }
        if connectionError != nil { return "Connection needs attention" }
        return tunnel.isStarting ? "Starting device connection…" : "Connecting to iPhone…"
    }

    @MainActor
    private func connectAutomatically() async {
        connectionError = nil
        guard let udid = devices.connectedUDID else { return }
        sidecar.stop()
        guard config.isValid else {
            connectionError = "The simulation runtime is missing. Reinstall the app’s runtime."
            return
        }
        // An existing daemon is reused; the system password prompt is only
        // requested if it must be started. Cancelling does not trigger a loop.
        await tunnel.ensureRunning()
        guard !Task.isCancelled, devices.connectedUDID == udid else { return }
        guard tunnel.isUp else {
            connectionError = tunnel.lastError ?? "The device connection could not start. Try again."
            return
        }
        // USB detection can precede developer-tunnel/device-image readiness.
        // Retry a few times without requesting administrator permission again.
        var failedAttempts = 0
        while failedAttempts < 3 {
            guard !Task.isCancelled, devices.connectedUDID == udid else { return }
            var wasReady = false
            sidecar.start(udid: udid)
            for _ in 0..<40 {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard devices.connectedUDID == udid else { return }
                switch sidecar.state {
                case .ready:
                    wasReady = true
                    // Stay attached so a dropped service reconnects automatically.
                    while sidecar.state.isReady || sidecar.isRestoring {
                        do { try await Task.sleep(for: .seconds(1)) } catch { return }
                        guard devices.connectedUDID == udid else { return }
                    }
                case .launching: continue
                default: break
                }
                break
            }
            guard !Task.isCancelled else { return }
            // A completed restore intentionally closes a healthy session;
            // it must not consume the retry budget for connection failures.
            failedAttempts = wasReady ? 0 : failedAttempts + 1
            if failedAttempts < 3 {
                sidecar.stop()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        connectionError = sidecar.lastError ?? "Couldn’t connect. Unlock your iPhone, trust this Mac, and check Developer Mode."
        sidecar.stop()
    }

    private var hasSimulatedLocation: Bool {
        sidecar.state.isReady && engine.currentCoordinate != nil
    }

    private var displayedCoordinate: CLLocationCoordinate2D? {
        guard devices.hasDevice else { return nil }
        return hasSimulatedLocation ? engine.currentCoordinate : macLocation.location?.coordinate
    }

    private func centerOnDisplayedLocation() {
        guard following, let coordinate = displayedCoordinate else { return }
        let span = hasSimulatedLocation ? 1500 : max(1500, (macLocation.location?.horizontalAccuracy ?? 0) * 4)
        mapController.center(on: coordinate, meters: span)
    }

    private var sidebarSearch: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search a place or address", text: $search.query)
                    .textFieldStyle(.plain)
                    .onSubmit { search.run(near: mapController.currentCenter?()) }
                    .onChange(of: search.query) { _, _ in search.run(near: mapController.currentCenter?()) }
                if search.isSearching { ProgressView().controlSize(.small) }
                if !search.query.isEmpty {
                    Button { search.clear() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                }
            }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            if !search.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(search.results.prefix(6).enumerated()), id: \.offset) { _, item in
                        Button {
                            following = false
                            mapController.center(on: item.coordinate, meters: 1500)
                            if mode == .route { engine.addWaypoint(item.coordinate) }
                            else { mode = .teleport; selection = item.coordinate }
                            search.clear()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayTitle).font(.callout.weight(.medium)).lineLimit(2)
                                Text(item.displaySubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }.frame(maxWidth: .infinity)
    }

    private var routeControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your route").font(.headline)
                Spacer()
                Text("\(engine.waypoints.count) stops").font(.caption).foregroundStyle(.secondary)
            }
            if engine.waypoints.isEmpty {
                Text("Add two or more stops on the map to start moving.").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text("Speed").font(.callout)
                Spacer()
                Text("\(Int(engine.speedKmh)) km/h").font(.callout.monospacedDigit())
            }
            Slider(value: $engine.speedKmh, in: 1...300)
            HStack {
                preset("Walk", speed: 5)
                preset("Cycle", speed: 18)
                preset("Drive", speed: 50)
            }
            Toggle("Repeat route", isOn: $engine.loop).font(.callout)
            DisclosureGroup("More options", isExpanded: $advanced) {
                VStack(alignment: .leading) {
                    Text("GPS variation · \(Int(engine.jitterMetres)) m").font(.caption)
                    Slider(value: $engine.jitterMetres, in: 0...20)
                }.padding(.top, 10)
            }.font(.caption)
            HStack {
                Button {
                    if engine.playback == .playing { engine.pause() } else { engine.play() }
                } label: {
                    Label(engine.playback == .playing ? "Pause" : (engine.playback == .paused ? "Resume" : "Start route"), systemImage: engine.playback == .playing ? "pause.fill" : "play.fill")
                }.buttonStyle(.borderedProminent).disabled(!canSimulate || engine.waypoints.count < 2)
                Button { engine.stop() } label: { Image(systemName: "stop.fill") }.disabled(engine.playback == .idle).help("Stop route")
            }
            if engine.playback != .idle { ProgressView(value: engine.progress) }
            if !engine.waypoints.isEmpty {
                Text(String(format: "%.2f km · about %.0f min", engine.totalDistance / 1000, engine.estimatedDurationSeconds / 60))
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear route") { engine.clearRoute() }.font(.caption)
            }
        }
    }

    private func preset(_ title: String, speed: Double) -> some View {
        Button(title) { engine.speedKmh = speed }.controlSize(.small)
    }
    private func handleTap(_ coordinate: CLLocationCoordinate2D) {
        guard canSimulate, mode != .explore else { return }
        following = false
        if mode == .route { engine.addWaypoint(coordinate) } else { selection = coordinate }
    }
    private func icon(_ mode: EditMode) -> String {
        switch mode { case .explore: return "iphone"; case .teleport: return "mappin.and.ellipse"; case .route: return "point.topleft.down.to.point.bottomright.curvepath" }
    }
    private func coordinateText(_ c: CLLocationCoordinate2D) -> String { String(format: "%.5f, %.5f", c.latitude, c.longitude) }
}
