import Combine
import Foundation

/// Polls the runtime's `usbmux` mode to detect whether an iPhone is plugged in,
/// independently of the developer tunnel. Used by the onboarding checklist so it
/// can tell the user "iPhone detected" before anything else is set up.
@MainActor
final class DeviceWatcher: ObservableObject {
    @Published private(set) var connectedDevices: [DeviceInfo] = []
    var deviceCount: Int { connectedDevices.count }
    private var explicitSelection: String?
    @Published private(set) var connectedUDID: String?

    var hasDevice: Bool { connectedUDID != nil }
    var selectedDevice: DeviceInfo? { connectedDevices.first { $0.udid == connectedUDID } }

    func select(_ udid: String) {
        guard connectedDevices.contains(where: { $0.udid == udid }) else { return }
        explicitSelection = udid
        connectedUDID = udid
    }


    private let launch: () -> (executable: URL, args: [String])
    private var timer: Timer?
    private var polling = false

    init(launch: @escaping () -> (executable: URL, args: [String])) {
        self.launch = launch
        let t = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { await poll() }
    }

    private func poll() async {
        guard !polling else { return }
        polling = true
        defer { polling = false }

        let (exe, args) = launch()
        guard FileManager.default.isExecutableFile(atPath: exe.path) else { return }

        let connected: [DeviceInfo]? = await Task.detached {
            let proc = Process()
            proc.executableURL = exe
            proc.arguments = args
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = Pipe()
            do { try proc.run() } catch { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let devices = obj["devices"] as? [[String: Any]]
            else { return nil }
            // Network discovery can remain present after the cable is unplugged.
            // The map's connected state specifically represents USB attachment.
            return devices.filter { ($0["connection"] as? String) == "USB" }
                .compactMap { item in
                    guard let serial = item["serial"] as? String else { return nil }
                    return DeviceInfo(udid: serial, name: item["name"] as? String,
                                      productType: item["product_type"] as? String,
                                      productVersion: item["product_version"] as? String)
                }
        }.value

        if let connected {
            let previous = Dictionary(connectedDevices.map { ($0.udid, $0) }, uniquingKeysWith: { first, _ in first })
            var unique: [String: DeviceInfo] = [:]
            for var device in connected {
                if let old = previous[device.udid] {
                    device.name = device.name ?? old.name
                    device.productType = device.productType ?? old.productType
                    device.productVersion = device.productVersion ?? old.productVersion
                }
                unique[device.udid] = device
            }
            connectedDevices = unique.values.sorted {
                if $0.isIPhone != $1.isIPhone { return $0.isIPhone }
                return $0.udid < $1.udid
            }
            if let explicitSelection, unique[explicitSelection] == nil { self.explicitSelection = nil }
            connectedUDID = DeviceSelection.preferred(in: connectedDevices, explicit: explicitSelection)
        }
    }
}
