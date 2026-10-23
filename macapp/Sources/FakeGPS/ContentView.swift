import CoreLocation
import MapKit
import SwiftUI

enum EditMode: String, CaseIterable, Identifiable {
    case explore = "My iPhone"
    case teleport = "Move to a place"
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
        ZStack(alignment: .leading) {
            ZStack(alignment: .top) {
                MapView(waypoints: engine.waypoints,
                        currentCoordinate: displayedCoordinate,
                        locationTitle: "\(deviceFamily) location",
                        locationAccessReady: macLocation.location != nil,
                        selectedCoordinate: mode == .teleport ? selection : nil,
                        canMoveToSelection: canSimulate,
                        onMoveToSelection: moveToSelection,
                        onDismissSelection: { selection = nil },
                        controller: mapController, onTap: handleTap,
                        onPan: { following = false })
                VStack(spacing: 12) {
                    deviceCard
                    if devices.hasDevice && mode != .explore {
                        Label(mode == .teleport ? "Choose a place, then click Move here" : "Click the map to add stops", systemImage: "hand.tap")
                            .font(.callout).padding(.horizontal, 16).padding(.vertical, 9)
                            .background(.regularMaterial, in: Capsule())
                    }
                }.padding(20).padding(.leading, 328)
            }
            sidebar.frame(width: 300).padding(14)
        }
        .disabled(macLocation.isAwaitingAuthorization)
        .accessibilityHidden(macLocation.isAwaitingAuthorization)
        .overlay {
            if macLocation.isAwaitingAuthorization {
                locationPermissionOverlay
            }
        }
        .frame(minWidth: 940, idealWidth: 1180, minHeight: 650, idealHeight: 760)
        .task(id: "\(devices.connectedUDID ?? "none")-\(connectionAttempt)") {
            await connectAutomatically()
        }
        .onChange(of: displayedCoordinate.map { [$0.latitude, $0.longitude] }) { _, _ in
            centerOnDisplayedLocation()
        }
        .onChange(of: devices.connectedUDID, initial: true) { _, udid in
            engine.stop()
            selection = nil
            mode = .explore
            restoreError = nil
            if udid != nil {
                following = true
                macLocation.request()
                centerOnDisplayedLocation()
            } else {
                macLocation.cancel()
                engine.clearRoute()
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

    private var locationPermissionOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            Text("Allow location access")
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Click “Allow” in the macOS permission dialog to center the map on your current location.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Text("We use this Mac’s location as the starting point for your connected device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            ProgressView("Waiting for your choice…")
                .controlSize(.small)
                .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .contentShape(Rectangle())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("iOS Fake GPS").font(.headline)
                    Text("Devices & locations").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !devices.connectedDevices.isEmpty {
                        Picker("Device", selection: Binding(
                            get: { devices.connectedUDID ?? "" },
                            set: { devices.select($0) }
                        )) {
                            ForEach(devices.connectedDevices) { device in
                                Text(device.selectionLabel + " · " + String(device.udid.suffix(4)))
                                    .tag(device.udid)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(10)
                        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                        .disabled(sidecar.isRestoring)
                    }
                    sidebarSearch
                    modeSection("Your device", [.explore])
                    modeSection("Edit location", [.teleport, .route])
                    if mode == .route {
                        routeControls.padding(14)
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                    }
                    if let restoreError { Text(restoreError).font(.caption).foregroundStyle(.orange) }
                    if let error = connectionError, devices.hasDevice {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.caption).foregroundStyle(.orange)
                            Button("Retry connection") { connectionAttempt += 1 }
                        }
                    } else if let error = sidecar.lastError, canSimulate {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            Divider().padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle().fill(sidecar.state.isReady ? .green : .secondary).frame(width: 7, height: 7)
                    Text(connectionStatus).font(.caption)
                    Spacer()
                }
                if sidecar.state.isReady {
                    Button(sidecar.isRestoring ? "Restoring location…" : "Restore real location") {
                        Task { await restoreLocation() }
                    }.buttonStyle(.bordered).controlSize(.large)
                        .disabled(sidecar.isRestoring)
                }
            }.padding(20)
        }
        .modifier(SidebarGlass())
    }

    /// One titled group of sidebar modes. Splitting "Your device" from
    /// "Edit location" keeps browsing the phone's real position visually
    /// separate from the two modes that change it.
    private func modeSection(_ title: String, _ items: [EditMode]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.leading, 12).padding(.bottom, 4)
            ForEach(items) { item in modeRow(item) }
        }
    }

    private func modeRow(_ item: EditMode) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { selection = nil; mode = item } } label: {
            HStack(spacing: 12) {
                Image(systemName: item == .explore && deviceFamily == "iPad" ? "ipad" : icon(item))
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 30, height: 30)
                Text(item == .explore ? "My \(deviceFamily)" : item.rawValue)
                Spacer()
                if mode == item { Image(systemName: "chevron.right").font(.caption2.weight(.bold)) }
            }
            .font(.system(size: 14, weight: mode == item ? .semibold : .regular))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(mode == item ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(mode == item ? Color.accentColor : .primary)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(mode == item ? .isSelected : [])
            .disabled(item != .explore && !canSimulate)
            .opacity(item != .explore && !canSimulate ? 0.4 : 1)
    }

    private var deviceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: devices.hasDevice ? (deviceFamily == "iPad" ? "ipad" : "iphone") : "iphone.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(devices.hasDevice ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(devices.hasDevice ? "\(deviceFamily) connected" : "No device connected")
                    .font(.headline)
                if !devices.hasDevice {
                    Text("Connect your iPhone or iPad with a USB cable.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if displayedCoordinate != nil {
                    Text("\(deviceFamily) location")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        if macLocation.isLocating { ProgressView().controlSize(.small) }
                        Text(macLocation.message).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !macLocation.isLocating {
                        Button(macLocation.needsLocationSettings ? "Open Location Settings" : "Try again") {
                            macLocation.retry()
                        }.font(.caption)
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

    private var deviceFamily: String { devices.selectedDevice?.family ?? "Device" }

    private var canSimulate: Bool {
        guard !sidecar.isRestoring, let selected = devices.connectedUDID,
              case let .ready(device) = sidecar.state else { return false }
        return device.udid == selected
    }

    private var connectionStatus: String {
        if !devices.hasDevice { return "Connect an iPhone or iPad to get started" }
        if sidecar.isRestoring { return "Restoring location…" }
        if canSimulate, case let .ready(device) = sidecar.state {
            let selected = devices.selectedDevice
            return DeviceInfo(udid: device.udid, name: selected?.name ?? device.name,
                              productType: selected?.productType ?? device.productType,
                              productVersion: selected?.productVersion ?? device.productVersion)
                .usbConnectionDescription
        }
        if connectionError != nil { return "Connection needs attention" }
        return tunnel.isStarting ? "Starting device connection…" : "Connecting to device…"
    }

    @MainActor
    private func connectAutomatically() async {
        connectionError = nil
        engine.stop()
        guard await sidecar.disconnectAndWait(), !Task.isCancelled else {
            if !Task.isCancelled { connectionError = "The previous device connection is still closing. Try again." }
            return
        }
        engine.clearRoute()
        guard let udid = devices.connectedUDID else { return }
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
            guard await sidecar.disconnectAndWait(), !Task.isCancelled,
                  devices.connectedUDID == udid else { return }
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
        connectionError = sidecar.lastError ?? "Couldn’t connect. Unlock your device, trust this Mac, and check Developer Mode."
        sidecar.stop()
    }

    private var hasSimulatedLocation: Bool {
        canSimulate && engine.currentCoordinate != nil
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
                    .onSubmit {
                        Task {
                            guard let item = await search.submit(near: mapController.currentCenter?())
                            else { return }
                            go(to: item)
                        }
                    }
                    .onChange(of: search.query) { _, _ in
                        search.update(near: mapController.currentCenter?())
                    }
                if search.isSearching { ProgressView().controlSize(.small) }
                if !search.query.isEmpty {
                    Button { search.clear() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                }
            }.padding(14).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            if !search.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(search.suggestions.prefix(6).enumerated()), id: \.offset) { _, item in
                        Button {
                            Task {
                                guard let resolved = await search.resolve(item) else { return }
                                go(to: resolved)
                            }
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

    /// Moves the map (and the current mode) to a search result, then clears the
    /// suggestion list.
    private func go(to item: MKMapItem) {
        following = false
        mapController.center(on: item.coordinate, meters: 1500)
        // Browsing the map is always allowed; picking a destination to push is
        // not, so leave the mode alone until a device is actually connected.
        if canSimulate {
            if mode == .route { engine.addWaypoint(item.coordinate) }
            else { mode = .teleport; selection = item.coordinate }
        }
        search.clear()
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
        if mode == .route {
            engine.addWaypoint(coordinate)
        } else {
            selection = coordinate
            // One click is the whole selection gesture here, so bring the pin to
            // the middle of the map; that also gives its card room to open.
            mapController.focus(on: coordinate)
        }
    }
    private func icon(_ mode: EditMode) -> String {
        switch mode { case .explore: return "iphone"; case .teleport: return "mappin.and.ellipse"; case .route: return "point.topleft.down.to.point.bottomright.curvepath" }
    }
    private func moveToSelection() {
        guard canSimulate, let selection else { return }
        engine.stop()
        engine.teleport(to: selection)
        self.selection = nil
        following = true
        centerOnDisplayedLocation()
    }
}
