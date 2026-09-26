// Native integration only. Model policy, downloads, hardware detection,
// inference lifecycle and the interface are owned by the C23 geist-app.
import AppKit
import Observation
import Sparkle
import SwiftUI

@main
struct GeistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("Geist", systemImage: "waveform.circle") {
            Text(delegate.runtime.status)
            Button("Open Geist") { delegate.runtime.open() }
                .disabled(delegate.runtime.url == nil)
                .keyboardShortcut("o")
            if !delegate.runtime.running {
                Button("Start Geist") { delegate.runtime.start() }
            }
            Divider()
            Toggle("Start at Login", isOn: Binding(
                get: { delegate.settings.launchAtLogin },
                set: { delegate.settings.setLaunchAtLogin($0) }))
            Button("Show Data Folder") { NSWorkspace.shared.open(delegate.runtime.dataFolder) }
            Button("Check for Updates…") { delegate.updater.updater.checkForUpdates() }
            Divider()
            Button("Stop model service") { delegate.runtime.stop() }
            Button("Quit menu bar") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    @MainActor let runtime = ApplicationProcess()
    @MainActor let settings = Settings()
    @MainActor lazy var updater = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        ApplicationProcess.stopForUpdate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            do { try updater.updater.start() } catch {
                FileHandle.standardError.write(Data("Geist update service: \(error.localizedDescription)\n".utf8))
            }
            runtime.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { runtime.open() }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }
}

@MainActor
@Observable
final class ApplicationProcess {
    private(set) var url: URL?
    private(set) var status = "Starting…"
    private(set) var running = false
    private var working = false

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

    nonisolated static func stopForUpdate() { _ = service(["stop"]) }

    func start() {
        guard !working else { return }
        working = true
        status = "Starting local service…"
        Task {
            let result = await Task.detached { Self.service(["start"]) }.value
            if result.0 == 0 {
                let connection = await Task.detached { Self.service(["connection"]) }.value
                if connection.0 == 0,
                   let data = try? JSONSerialization.jsonObject(with: connection.1) as? [String: Any],
                   let base = data["base_url"] as? String,
                   let key = data["api_key"] as? String,
                   key.count == 64,
                   let endpoint = URL(string: base), endpoint.host == "127.0.0.1",
                   let port = endpoint.port {
                    url = URL(string: "http://127.0.0.1:\(port)/#\(key)")
                    running = true
                    status = "Local service running"
                    if ProcessInfo.processInfo.environment["GEIST_NO_OPEN"] == nil { open() }
                } else { status = "Cannot read service connection" }
            } else { status = "Service unavailable — check port 8766" }
            working = false
            if ProcessInfo.processInfo.environment["GEIST_TEST_QUIT"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
            }
        }
    }

    func open() { if let url { NSWorkspace.shared.open(url) } }

    func stop() {
        guard !working else { return }
        working = true
        Task {
            let result = await Task.detached { Self.service(["stop"]) }.value
            if result.0 == 0 { running = false; url = nil; status = "Local service stopped" }
            else { status = "Could not stop service" }
            working = false
        }
    }
}
