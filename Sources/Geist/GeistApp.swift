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
            Button("Quit Geist") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let runtime = ApplicationProcess()
    @MainActor let settings = Settings()
    @MainActor let updater = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

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
        MainActor.assumeIsolated { runtime.stop() }
        return .terminateNow
    }
}

@MainActor
@Observable
final class ApplicationProcess {
    private(set) var url: URL?
    private(set) var status = "Starting…"
    private(set) var running = false
    private var process: Process?
    private var stdout = ""
    private var stopping = false

    var dataFolder: URL {
        if let path = ProcessInfo.processInfo.environment["GEIST_HOME"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Geist", isDirectory: true)
    }

    func start() {
        guard process == nil else { open(); return }
        url = nil; stdout = ""; status = "Starting…"; stopping = false
        let child = Process()
        let directory = Bundle.main.executableURL!.deletingLastPathComponent()
        child.executableURL = directory.appendingPathComponent("geist-app")
        child.arguments = ["--port", "0", "--home", dataFolder.path,
                           "--daemon", directory.appendingPathComponent("geistd").path]
        // Explicit developer fixture; the C23 application owns validation/loading.
        if let model = ProcessInfo.processInfo.environment["GEIST_MODEL"] {
            child.arguments! += ["--model", model]
        }
        let output = Pipe(), errors = Pipe()
        child.standardOutput = output; child.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.read(text) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { FileHandle.standardError.write(data) }
        }
        child.terminationHandler = { [weak self] child in
            Task { @MainActor in
                guard let self, self.process === child else { return }
                self.running = false; self.process = nil; self.url = nil
                if !self.stopping && child.terminationStatus != 0 {
                    self.status = "Stopped (exit \(child.terminationStatus))"
                    let alert = NSAlert()
                    alert.messageText = "Geist could not keep running"
                    alert.informativeText = "Another copy may already be running. Quit it and try again. The data folder contains server.log for model errors."
                    if ProcessInfo.processInfo.environment["GEIST_NO_OPEN"] == nil { alert.runModal() }
                } else { self.status = "Stopped" }
            }
        }
        do {
            try child.run(); process = child; running = true
        } catch {
            status = "Could not start: \(error.localizedDescription)"
        }
    }

    private func read(_ text: String) {
        guard url == nil else { return }
        stdout += text
        guard stdout.utf8.count <= 8192 else { status = "Invalid launcher response"; stop(); return }
        while let newline = stdout.firstIndex(of: "\n") {
            let line = String(stdout[..<newline]); stdout.removeSubrange(...newline)
            guard line.hasPrefix("GEIST_APP_URL="),
                  let link = URL(string: String(line.dropFirst("GEIST_APP_URL=".count))),
                  link.scheme == "http", link.host == "127.0.0.1", link.port != nil,
                  link.fragment?.count == 64 else { continue }
            url = link; status = "Runs here. Stays here."
            if ProcessInfo.processInfo.environment["GEIST_NO_OPEN"] == nil { open() }
            if ProcessInfo.processInfo.environment["GEIST_TEST_QUIT"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
            }
        }
    }

    func open() { if let url { NSWorkspace.shared.open(url) } }

    func stop() {
        stopping = true
        guard let child = process else { return }
        if child.isRunning { child.terminate() }
        let deadline = Date().addingTimeInterval(15)
        while child.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        // C23 cleanup is bounded. Do not kill an unrelated process by name.
        if child.isRunning {
            let pid = child.processIdentifier
            kill(getpgid(pid) == pid ? -pid : pid, SIGKILL)
        }
        process = nil; running = false; url = nil
    }
}
