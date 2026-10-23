import Combine
import Foundation

/// A device reported by the Python sidecar.
struct DeviceInfo: Identifiable, Hashable, Codable {
    var udid: String
    var name: String?
    var productType: String?
    var productVersion: String?

    var id: String { udid }
    var display: String {
        let model = productType ?? "iPhone"
        let os = productVersion.map { " · iOS \($0)" } ?? ""
        return "\(name ?? model)\(os)"
    }

    enum CodingKeys: String, CodingKey {
        case udid, name
        case productType = "product_type"
        case productVersion = "product_version"
    }
}

enum SidecarState: Equatable {
    case stopped
    case launching
    case ready(DeviceInfo)
    case failed(String)

    var isReady: Bool { if case .ready = self { return true }; return false }
}

/// Manages the lifetime of the `gpsd_helper.py` sidecar process and the
/// newline-delimited JSON protocol spoken over its stdin/stdout pipes.
@MainActor
final class Sidecar: ObservableObject {
    @Published private(set) var state: SidecarState = .stopped
    @Published private(set) var lastError: String?
    @Published private(set) var isRestoring = false

    /// Executable to launch and the leading args (e.g. the frozen runtime with
    /// ["sidecar"], or python with [scriptPath]).
    var executableURL: URL
    var argsPrefix: [String]

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutBuffer = Data()
    private var messageID = 0
    private var generation = UUID()
    private var pendingClear: (id: Int, reply: CheckedContinuation<Bool, Never>)?
    private var clearTimeout: Task<Void, Never>?

    init(executableURL: URL, argsPrefix: [String]) {
        self.executableURL = executableURL
        self.argsPrefix = argsPrefix
    }

    // MARK: - Lifecycle

    func start(udid: String? = nil) {
        stop()
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            state = .failed("Runtime not found at \(executableURL.path).")
            return
        }

        state = .launching
        lastError = nil

        let generation = self.generation
        let proc = Process()
        proc.executableURL = executableURL
        var args = argsPrefix
        if let udid { args += ["--udid", udid] }
        proc.arguments = args

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let self else { return }
            Task { @MainActor in
                guard self.generation == generation else { return }
                self.ingest(data)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let s = String(data: data, encoding: .utf8), !s.isEmpty {
                FileHandle.standardError.write(Data(s.utf8))
            }
        }
        proc.terminationHandler = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.generation == generation else { return }
                self.handleTermination()
            }
        }

        do {
            try proc.run()
        } catch {
            state = .failed("Could not launch sidecar: \(error.localizedDescription)")
            return
        }
        process = proc
        stdinPipe = inPipe
    }

    func stop() {
        if let proc = process, proc.isRunning {
            // Reset the device to real GPS first, then ask the helper to quit.
            // Don't SIGTERM immediately — that races the clear. Close stdin so it
            // exits cleanly, and force-kill only if it lingers.
            send(["cmd": "clear"])
            send(["cmd": "quit"])
            try? stdinPipe?.fileHandleForWriting.close()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if proc.isRunning { proc.terminate() }
            }
        }
        resetState()
    }

    /// Blocking cleanup used on app termination: clear the location and wait
    /// (bounded) for the helper to exit, so quitting always restores real GPS.
    func shutdownBlocking() {
        guard let proc = process, proc.isRunning else { return }
        send(["cmd": "clear"])
        send(["cmd": "quit"])
        try? stdinPipe?.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(2)
        while proc.isRunning && Date() < deadline { usleep(50_000) }
        if proc.isRunning { proc.terminate() }
        resetState()
    }

    private func resetState() {
        finishClear(false)
        generation = UUID()
        process = nil
        stdinPipe = nil
        stdoutBuffer.removeAll()
        if case .ready = state { state = .stopped }
        if case .launching = state { state = .stopped }
    }

    private func handleTermination() {
        finishClear(false)
        process = nil
        stdinPipe = nil
        if state.isReady || state == .launching {
            state = .stopped
        }
    }

    // MARK: - Commands

    func setLocation(_ lat: Double, _ lon: Double) {
        guard state.isReady, !isRestoring else { return }
        messageID += 1
        send(["cmd": "set", "lat": lat, "lon": lon, "id": messageID])
    }

    func clearLocation() {
        messageID += 1
        send(["cmd": "clear", "id": messageID])
    }

    /// The helper's acknowledgement confirms the reset command was sent,
    /// not a GPS sensor reading. Release the old developer session before any
    /// automatic reconnection, matching the cleanup performed by an app restart.
    func restoreLocation() async -> Bool {
        guard state.isReady, !isRestoring, let proc = process else { return false }
        isRestoring = true
        lastError = nil
        defer { isRestoring = false }
        messageID += 1
        let id = messageID
        let acknowledged = await withCheckedContinuation { continuation in
            pendingClear = (id, continuation)
            clearTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(6)) } catch { return }
                self?.finishClear(false)
            }
            if !send(["cmd": "clear", "id": id]) { finishClear(false) }
        }
        guard acknowledged else {
            lastError = lastError ?? "The reset was not acknowledged. Try restoring again."
            return false
        }
        send(["cmd": "quit"])
        try? stdinPipe?.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(6)
        while proc.isRunning && Date() < deadline {
            do { try await Task.sleep(for: .milliseconds(100)) } catch {
                lastError = "Reset interrupted before the connection closed."
                return false
            }
        }
        guard !proc.isRunning else {
            // Do not start another session while cleanup is still outstanding.
            lastError = "The reset was sent, but the old connection has not closed. Try again."
            return false
        }
        resetState()
        return true
    }

    private func finishClear(_ success: Bool) {
        clearTimeout?.cancel()
        clearTimeout = nil
        let pending = pendingClear
        pendingClear = nil
        pending?.reply.resume(returning: success)
    }

    @discardableResult
    private func send(_ obj: [String: Any]) -> Bool {
        guard let pipe = stdinPipe,
              let data = try? JSONSerialization.data(withJSONObject: obj) else { return false }
        var line = data
        line.append(0x0A) // newline
        do {
            try pipe.fileHandleForWriting.write(contentsOf: line)
            return true
        } catch {
            lastError = "Could not send the device command: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Incoming NDJSON

    private func ingest(_ data: Data) {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[stdoutBuffer.startIndex ..< nl]
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex ... nl)
            guard !lineData.isEmpty else { continue }
            handleEvent(lineData)
        }
    }

    private func handleEvent(_ lineData: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let event = obj["event"] as? String else { return }

        switch event {
        case "ready":
            if let devObj = obj["device"],
               let devData = try? JSONSerialization.data(withJSONObject: devObj),
               let dev = try? JSONDecoder().decode(DeviceInfo.self, from: devData) {
                state = .ready(dev)
            } else {
                state = .ready(DeviceInfo(udid: "?", name: "Device", productType: nil, productVersion: nil))
            }
        case "error":
            let msg = obj["message"] as? String ?? "unknown error"
            lastError = msg
            if let id = obj["id"] as? Int, id == pendingClear?.id { finishClear(false) }
            if (obj["fatal"] as? Bool) == true {
                state = .failed(msg)
            }
        case "ok":
            if let id = obj["id"] as? Int, id == pendingClear?.id { finishClear(true) }
        case "pong", "devices", "bye":
            break
        default:
            break
        }
    }
}
