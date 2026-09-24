// Geist — the menu bar app around geist-serve.
import AppKit
import SwiftUI

@main
struct GeistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContent(server: delegate.server, models: delegate.models, settings: delegate.settings,
                        openLog: { openWindow(id: "log") })
        } label: {
            Image(systemName: delegate.server.isRunning ? "waveform.circle.fill" : "waveform.circle")
        }
        Window("geist-serve log", id: "log") { LogView(server: delegate.server) }
            .defaultSize(width: 720, height: 420)
    }
}

/// Owns server and models for the app's lifetime; stops the server before
/// the app quits so no geist-serve outlives its menu bar icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let server = ServerProcess(
        port: Int(ProcessInfo.processInfo.environment["GEIST_PORT"] ?? "") ?? 11434)
    @MainActor let models = ModelStore()
    @MainActor let settings = Settings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            server.host = settings.host
            models.onReady = { [server, settings] url in
                settings.enableLaunchAtLoginOnce()
                server.stop(); server.start(model: url)
            }
            if ProcessInfo.processInfo.environment["GEIST_AUTO_CLI"] != nil { settings.installCLI() } // test hook
            if let m = models.selected {
                server.start(model: m)
            } else {
                showWelcome()
            }
            // Test/dev hook: start a curated download at launch.
            if let id = ProcessInfo.processInfo.environment["GEIST_AUTO_DOWNLOAD"], let m = Models.byID(id) {
                models.download(m)
            }
        }
    }

    /// First launch: a plain AppKit window hosting the SwiftUI view, because
    /// a menu-bar app has no window scene to open from the delegate.
    @MainActor private var welcome: NSWindow?
    @MainActor func showWelcome() {
        let w = NSWindow(contentViewController: NSHostingController(
            rootView: WelcomeView(models: models, close: { [weak self] in self?.welcome?.close() })))
        w.title = "Welcome to Geist"
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        welcome = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { server.stop() }
        return .terminateNow
    }
}

struct MenuContent: View {
    let server: ServerProcess
    let models: ModelStore
    let settings: Settings
    let openLog: () -> Void

    var body: some View {
        Text("geist-serve – \(server.statusText)")
        if let e = models.lastError { Text(e).foregroundStyle(.red) }
        Divider()
        Menu("Model") {
            ForEach(Models.curated) { m in
                Button { pick(m) } label: {
                    Text(label(for: m))
                }
                .disabled(models.isDownloading(m))
            }
            if !models.custom.isEmpty {
                Divider()
                ForEach(models.custom, id: \.self) { url in
                    Button { use(url) } label: {
                        Text((models.isSelected(url) ? "✓ " : "   ") + url.lastPathComponent)
                    }
                }
            }
            Divider()
            Button("Add GGUF File…") { if let u = models.addCustom() { use(u) } }
        }
        if case .portInUse = server.state {
            Button("Quit Ollama and start") {
                ServerProcess.quitOllama()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { server.restart() }
            }
        }
        if server.isRunning {
            Button("Stop Server") { server.stop() }
        } else if let m = models.selected {
            Button("Start Server") { server.start(model: m) }
        }
        Divider()
        Toggle("Start at Login", isOn: Binding(
            get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
        Toggle("Reachable on the Network", isOn: Binding(
            get: { settings.networkReachable },
            set: { on in
                settings.setNetworkReachable(on)
                server.host = settings.host
                if server.isRunning || server.state == .starting { server.restart() }
            }))
            .help("Listens on 0.0.0.0:11434. There is no authentication.")
        cliItem
        Button("Show Log") { openLog(); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Quit Geist") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder private var cliItem: some View {
        switch settings.cli {
        case .homebrew:
            Button("Command Line Tool: via Homebrew") {}.disabled(true)
        case .installed:
            Button("✓ Command Line Tool Installed") {}.disabled(true)
        case .stale:
            Button("Repair Command Line Tool…") { settings.installCLI() }
        case .none:
            Button("Install Command Line Tool…") { settings.installCLI() }
        }
    }

    private func label(for m: CuratedModel) -> String {
        if let p = models.progress[m.id] { return "   \(m.name)  \(Int(p * 100)) %" }
        let mark = models.isSelected(models.path(m)) ? "✓ " : "   "
        let state = models.isPresent(m) ? "" : "  ↓"
        return "\(mark)\(m.name)  (\(m.sizeText))\(state)"
    }

    private func pick(_ m: CuratedModel) {
        if models.isPresent(m) { use(models.path(m)) } else { models.download(m) }
    }

    private func use(_ url: URL) {
        models.select(url)
        settings.enableLaunchAtLoginOnce()
        server.stop()
        server.start(model: url)
    }
}

/// First launch: nothing selected. Offer the default with its size, or any
/// other curated model, or a file.
struct WelcomeView: View {
    let models: ModelStore
    let close: () -> Void
    private let def = Models.byID(Models.defaultID)!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Geist needs a model").font(.title2).bold()
            Text("Geist runs one local model behind the Ollama and OpenAI APIs on port 11434. "
                 + "Nothing leaves your Mac. The download comes from Hugging Face and is checksum-verified.")
                .fixedSize(horizontal: false, vertical: true)
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(def.name)  ·  \(def.sizeText)  ·  needs \(def.minRAMGB) GB RAM").bold()
                    Text(def.note).foregroundStyle(.secondary)
                    if let p = models.progress[def.id] {
                        ProgressView(value: p).padding(.top, 4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Choose GGUF File…") { if models.addCustom() != nil { done() } }
                Spacer()
                Menu("Other model") {
                    ForEach(Models.curated.filter { $0.id != def.id }) { m in
                        Button("\(m.name)  (\(m.sizeText), \(m.minRAMGB) GB RAM)") { models.download(m) }
                    }
                }.fixedSize()
                Button(models.isDownloading(def) ? "Downloading…" : "Download \(def.name)") { models.download(def) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(models.isDownloading(def))
            }
            if let e = models.lastError { Text(e).foregroundStyle(.red) }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: models.selected) { _, s in if s != nil { done() } }
    }

    private func done() { close() }
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
