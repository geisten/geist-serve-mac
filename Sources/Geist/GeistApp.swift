// Geist — the menu bar app around geist-serve.
import AppKit
import SwiftUI

@main
struct GeistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContent(server: delegate.server, openLog: { openWindow(id: "log") })
        } label: {
            Image(systemName: delegate.server.isRunning ? "waveform.circle.fill" : "waveform.circle")
        }
        Window("geist-serve log", id: "log") {
            LogView(server: delegate.server)
        }
        .defaultSize(width: 720, height: 420)
    }
}

/// Owns the server for the app's lifetime; stops it before the app quits so
/// no geist-serve outlives its menu bar icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let server = ServerProcess(
        port: Int(ProcessInfo.processInfo.environment["GEIST_PORT"] ?? "") ?? 11434)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let m = ModelStore.selectedModel { Task { @MainActor in server.start(model: m) } }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { server.stop() }
        return .terminateNow
    }
}

struct MenuContent: View {
    let server: ServerProcess
    let openLog: () -> Void

    var body: some View {
        Text("geist-serve – \(server.statusText)")
        Divider()
        if case .portInUse = server.state {
            Button("Quit Ollama and start") {
                ServerProcess.quitOllama()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { server.restart() }
            }
        }
        if server.isRunning {
            Button("Stop Server") { server.stop() }
        } else if let m = ModelStore.selectedModel {
            Button("Start Server") { server.start(model: m) }
        }
        Button("Choose GGUF File…") {
            if let m = ModelStore.chooseFile() { server.stop(); server.start(model: m) }
        }
        Button("Show Log") { openLog(); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Quit Geist") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct LogView: View {
    let server: ServerProcess

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(server.log.enumerated()), id: \.offset) { i, line in
                        Text(line).font(.system(.caption, design: .monospaced)).id(i)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: server.log.count) { _, n in if n > 0 { proxy.scrollTo(n - 1) } }
        }
    }
}
