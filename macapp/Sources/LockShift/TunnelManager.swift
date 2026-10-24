import Combine
import Foundation

/// Tracks and (optionally) launches the privileged `tunneld` daemon.
///
/// `tunneld` is what creates the per-device RemoteXPC tunnel and auto-mounts the
/// Developer Disk Image. It must run as root, so we can only *start* it via an
/// authenticated `osascript` prompt; we poll its HTTP endpoint to know if it's up.
@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var isUp = false
    @Published private(set) var isStarting = false
    @Published private(set) var lastError: String?

    private var pollTimer: Timer?
    /// Returns (executablePath, args) for launching the tunnel daemon.
    let tunneldCommand: () -> (path: String, args: [String])

    init(tunneldCommand: @escaping () -> (path: String, args: [String])) {
        self.tunneldCommand = tunneldCommand
        startPolling()
    }

    private func startPolling() {
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        Task { await poll() }
    }

    private func poll() async {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:49151")!)
        req.timeoutInterval = 1.0
        let up: Bool
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            up = (resp as? HTTPURLResponse) != nil
        } catch {
            up = false
        }
        if up != isUp { isUp = up }
    }

    /// Launch tunneld with administrator privileges. Shows the macOS auth dialog.
    /// Runs detached so it keeps managing tunnels after this call returns.
    static let logPath = "/tmp/lockshift-tunneld.log"

    func startTunneld() {
        Task { await ensureRunning() }
    }

    /// Check first, then ask for administrator permission at most once per attempt.
    func ensureRunning() async {
        await poll()
        guard !isUp, !Task.isCancelled else { return }
        if isStarting {
            // A quick unplug/replug can overlap the existing password prompt.
            // Wait for that attempt instead of creating another prompt.
            while isStarting {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
            await poll()
            return
        }
        isStarting = true
        lastError = nil
        defer { isStarting = false }

        let (path, args) = tunneldCommand()
        let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
        let quotedArgs = args.map(quote).joined(separator: " ")
        // Fully detach the daemon so it survives the privileged osascript session
        // ending. `nohup` fails here ("can't detach from console" — no tty), and
        // a plain `&` child can be reaped with the session, so we use perl's
        // setsid to start a brand-new session, then exec the daemon. Output goes
        // to a log file; `&` returns control to osascript immediately.
        let inner = "/usr/bin/perl -MPOSIX -e 'setsid or exit 1; exec @ARGV' "
            + "\(quote(path)) \(quotedArgs)"
        let shell = "\(inner) </dev/null >\(Self.logPath) 2>&1 &"
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let error: String? = await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            let errors = Pipe()
            proc.standardError = errors
            do { try proc.run() } catch { return error.localizedDescription }
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 ? nil
                : (String(data: data, encoding: .utf8) ?? "Tunnel permission was not granted.")
        }.value
        if let error { lastError = error; return }
        guard !Task.isCancelled else { return }
        // The launcher returns before the daemon has opened its listening socket.
        for _ in 0..<15 {
            await poll()
            if isUp || Task.isCancelled { return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
        lastError = "Couldn’t start the device connection. Try again."
    }
}
