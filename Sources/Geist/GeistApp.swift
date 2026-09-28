// Native integration only. Model policy, downloads, hardware detection,
// inference lifecycle and the interface are owned by the C23 geist-app.
import AppKit
import Observation
import Sparkle
import SwiftUI

@main
struct GeistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("interfaceLanguage") private var interfacePreference = "system"
    var body: some Scene {
        let _ = interfacePreference // Refresh menu labels when the shared interface preference changes.
        MenuBarExtra("Geist", systemImage: "waveform.circle") {
            Text(desktopText(delegate.runtime.status))
                .onAppear { delegate.runtime.refresh() }
            if !delegate.runtime.modelName.isEmpty { Text(delegate.runtime.modelName) }
            Button(desktopText("Models & performance")) { delegate.runtime.open(destination: .models) }

                .keyboardShortcut("o")
            Button(desktopText("Connect a program")) { delegate.runtime.open(destination: .connect) }
            if !delegate.runtime.running {
                Button(desktopText("Start Geist")) { delegate.runtime.start() }
            }
            Divider()
            Toggle(desktopText("Start at Login"), isOn: Binding(
                get: { delegate.settings.launchAtLogin },
                set: { delegate.settings.setLaunchAtLogin($0) }))
            Button(desktopText("Show Data Folder")) { NSWorkspace.shared.open(delegate.runtime.dataFolder) }
            Button(desktopText("Check for Updates…")) { delegate.updater.updater.checkForUpdates() }
            Divider()
            Button(desktopText("Stop model service")) { delegate.runtime.confirmStop() }
            Button(desktopText("Quit Geist")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    @MainActor let runtime = ApplicationProcess()
    @MainActor let settings = Settings()
    @MainActor let updateShutdown = UpdateShutdown()
    @MainActor lazy var updater = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        MainActor.assumeIsolated { updateShutdown.mayInstall }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            runtime.updateStopping()
            updateShutdown.prepare(stop: { ApplicationProcess.stopForUpdate() }) { stopped in
                if !stopped { self.runtime.updateStopFailed() }
                // Sparkle rechecks updaterShouldRelaunchApplication before
                // resuming. Calling it after failure causes a clean abort.
                installHandler()
            }
        }
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: Error?) {
        MainActor.assumeIsolated { updateShutdown.reset() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            do { try updater.updater.start() } catch {
                FileHandle.standardError.write(Data("Geist update service: \(error.localizedDescription)\n".utf8))
            }
            NSApp.setActivationPolicy(.regular)
            Task { @MainActor in
                guard await LaunchInstallation.prepare() else { NSApp.terminate(nil); return }
                runtime.start()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { runtime.open() }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Quitting during a postponed update must not let Sparkle's helper
        // replace the bundle before the shared service has stopped.
        MainActor.assumeIsolated {
            updateShutdown.mayInstall ? .terminateNow : .terminateCancel
        }
    }
}

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
            if result.0 == 42 {
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
                    if ProcessInfo.processInfo.environment["GEIST_NO_OPEN"] == nil { open() }
                } else { status = "Cannot read service connection" }
            } else {
                url = nil; running = false
                status = result.0 == 43 ? "Finish the current task, then reconnect to update Geist."
                    : result.0 == 44 ? "A newer Geist service is running. Open the newest installed app."
                    : result.0 == 42 ? "Restart the older service to use this app."
                    : "Service unavailable — check port 8766"
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
