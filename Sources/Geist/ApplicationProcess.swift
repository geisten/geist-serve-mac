// The one client of geist-cli: starts, watches and stops the shared model
// service and feeds its state to the menu and the desktop window.
import AppKit
import Observation

@MainActor
@Observable
final class ApplicationProcess {
    private(set) var url: URL?
    private(set) var status = "Starting…"
    private(set) var running = false
    private(set) var modelName = ""
    private var working = false
    @ObservationIgnored private var monitor: Timer?
    @ObservationIgnored lazy var desktop = DesktopWindow(retry: { [weak self] in self?.start() })

    private var showsWindow: Bool { ProcessInfo.processInfo.environment["GEIST_NO_OPEN"] == nil }
    private func changed() {
        if showsWindow { desktop.update(url: url, status: status, working: working) }
    }
    func confirmStop() {
        let alert = NSAlert()
        alert.messageText = desktopText("Stop model service?")
        alert.informativeText = desktopText("Terminal and editor connections will stop too. Downloaded models are kept.")
        alert.addButton(withTitle: desktopText("Stop model service"))
        alert.addButton(withTitle: desktopText("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { stop() }
    }

    var dataFolder: URL {
        if let path = ProcessInfo.processInfo.environment["GEIST_HOME"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Geist", isDirectory: true)
    }

    /// geist-cli exit codes the shell reacts to; anything else non-zero is "unavailable".
    enum Exit: Int32 {
        case ok = 0, olderServiceRunning = 42, serviceBusy = 43, newerServiceRunning = 44
    }

    // The CLI owns discovery/authentication. No native shell loads a second model.
    nonisolated private static func service(_ arguments: [String]) -> (Int32, Data) {
        let child = Process()
        child.executableURL = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("geist-cli")
        child.arguments = arguments
        let output = Pipe()
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            return (child.terminationStatus, data)
        } catch { return (-1, Data()) }
    }

    nonisolated static func stopForUpdate() -> Bool { service(["stop"]).0 == 0 }

    func updateStopFailed() {
        status = "Update cancelled — could not stop the model service. Try Stop model service first."
    }

    func updateStopping() {
        status = "Stopping model service before installing the update…"
    }

    func start() {
        guard !working else { return }
        working = true
        status = "Starting local service…"
        changed()
        if showsWindow { desktop.present() }
        if monitor == nil {
            monitor = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        Task {
            var result = await Task.detached { Self.service(["start"]) }.value
            if result.0 == Exit.olderServiceRunning.rawValue {
                let alert = NSAlert()
                alert.messageText = desktopText("Restart the older model service?")
                alert.informativeText = desktopText("Finish any current task first. Geist will use the installed version. Downloads and models are kept.")
                alert.addButton(withTitle: desktopText("Restart and continue"))
                alert.addButton(withTitle: desktopText("Cancel"))
                if alert.runModal() == .alertFirstButtonReturn {
                    result = await Task.detached { Self.service(["restart"]) }.value
                }
            }
            if result.0 == 0 {
                let connection = await Task.detached { Self.service(["connection"]) }.value
                if connection.0 == 0,
                   let data = try? JSONSerialization.jsonObject(with: connection.1) as? [String: Any],
                   let base = data["base_url"] as? String,
                   let key = data["api_key"] as? String,
                   DesktopPolicy.validKey(key),
                   let endpoint = URL(string: base), endpoint.scheme == "http", endpoint.host == "127.0.0.1",
                   endpoint.user == nil, endpoint.password == nil,
                   let port = endpoint.port {
                    url = URL(string: "http://127.0.0.1:\(port)/#\(key)")
                    running = true
                    status = "Local service running"
                    if showsWindow { open() }
                } else { status = "Cannot read service connection" }
            } else {
                url = nil; running = false
                status = switch Exit(rawValue: result.0) {
                case .serviceBusy: "Finish the current task, then reconnect to update Geist."
                case .newerServiceRunning: "A newer Geist service is running. Open the newest installed app."
                case .olderServiceRunning: "Restart the older service to use this app."
                default: "Service unavailable — check port 8766"
                }
            }
            working = false
            changed()
            if ProcessInfo.processInfo.environment["GEIST_TEST_QUIT"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
            }
        }
    }

    func open(destination: DesktopDestination? = nil) {
        desktop.update(url: url, status: desktopText(status), working: working)
        desktop.present(destination: destination)
    }

    // Another client may stop the shared service while the menu remains open.
    func refresh() {
        guard !working else { return }
        working = true
        Task {
            let result = await Task.detached { Self.service(["status"]) }.value
            if result.0 != 0 {
                running = false
                url = nil
                status = "Local service stopped"
                modelName = ""
            } else if let data = try? JSONSerialization.jsonObject(with: result.1) as? [String: Any] {
                let models = data["models"] as? [[String: Any]] ?? []
                let activeID = data["active_id"] as? String
                modelName = models.first(where: { $0["id"] as? String == activeID })?["name"] as? String ?? ""
                if modelName.isEmpty, let active = data["active"] as? String, !active.isEmpty {
                    modelName = URL(fileURLWithPath: active).lastPathComponent
                }
                status = (data["loading"] as? Bool == true || !(data["phase"] as? String ?? "").isEmpty) ? "Preparing model…"
                    : data["ready"] as? Bool == true ? (data["busy"] as? Bool == true ? "Model in use" : "Model ready") : "No model loaded"
            }
            working = false
            changed()
        }
    }

    func stop() {
        guard !working else { return }
        working = true
        Task {
            let result = await Task.detached { Self.service(["stop"]) }.value
            if result.0 == 0 { running = false; url = nil; modelName = ""; status = "Local service stopped" }
            else { status = "Could not stop service" }
            working = false
            changed()
        }
    }
}
