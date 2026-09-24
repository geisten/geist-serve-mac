// Geist — the menu bar app around geist-serve.
import AppKit
import Sparkle
import SwiftUI

@main
struct GeistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContent(server: delegate.server, models: delegate.models, settings: delegate.settings,
                        updater: delegate.updater.updater, openLog: { openWindow(id: "log") })
        } label: {
            MenuBarGlyph()
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
    /// Sparkle: automatic daily check, "Check for Updates…" in the menu.
    @MainActor let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: UpdaterDelegate.shared,
                                                          userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // Started explicitly so a refusal (unsigned bundle, odd location)
            // is a log line instead of a silently dead menu item.
            do { try updater.updater.start() } catch {
                FileHandle.standardError.write(Data("[geist] sparkle: \(error.localizedDescription)\n".utf8))
            }
            if let snap = ProcessInfo.processInfo.environment["GEIST_SNAPSHOT_WELCOME"] {
                // design/test hook: show the real window, photograph it, quit
                showWelcome()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                    WelcomeSnapshot.capture(window: welcome, to: snap)
                    NSApp.terminate(nil)
                }
                return
            }
            if ProcessInfo.processInfo.environment["GEIST_UPDATE_PROBE"] != nil {
                updater.updater.checkForUpdateInformation() // test hook: no UI, delegate logs
            }
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
        w.title = "Welcome to Geist" // for the window menu and accessibility; not drawn
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.styleMask = [.titled, .closable, .fullSizeContentView]
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
    let updater: SPUUpdater
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
        Button("Check for Updates…") { updater.checkForUpdates() }
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

/// The menu bar mark: our template glyph from the bundle, the SF symbol
/// only when running unbundled (swift run).
struct MenuBarGlyph: View {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    var body: some View {
        if let img = Self.image { Image(nsImage: img) } else { Image(systemName: "waveform.circle") }
    }
}

/// First launch: nothing selected. One decision, set in type: the default
/// model as a quiet card, everything else a text button. Generous margins,
/// two type sizes, one accent (the system's), numbers tabular.
struct WelcomeView: View {
    let models: ModelStore
    let close: () -> Void
    private let def = Models.byID(Models.defaultID)!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 44, height: 44).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 8 }
                }
                Text("Geist").font(.system(size: 30, weight: .semibold, design: .default)).tracking(-0.5)
            }
            .padding(.bottom, 8)
            Text("One local model behind the Ollama and OpenAI APIs on port 11434.")
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 28)

            // the recommended model, as a card without a box
            VStack(alignment: .leading, spacing: 6) {
                Text("Recommended").font(.system(size: 11, weight: .medium)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Text(def.name).font(.system(size: 20, weight: .medium))
                Text("\(def.sizeText)  ·  \(def.minRAMGB) GB RAM  ·  text").font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(def.note).font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let p = models.progress[def.id] {
                    ProgressView(value: p).progressViewStyle(.linear).padding(.top, 10)
                    Text("\(Int(p * 100)) %").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 28)

            HStack(spacing: 18) {
                Button(models.isDownloading(def) ? "Downloading…" : "Download \(def.name)") { models.download(def) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(models.isDownloading(def))
                Menu("Other model") {
                    ForEach(Models.curated.filter { $0.id != def.id }) { m in
                        Button("\(m.name)  ·  \(m.sizeText)  ·  \(m.minRAMGB) GB RAM") { models.download(m) }
                    }
                }.menuStyle(.borderlessButton).fixedSize()
                Button("Open GGUF file…") { if models.addCustom() != nil { close() } }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 24)

            if let e = models.lastError {
                Text(e).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Downloaded from Hugging Face and checksum-verified. Nothing leaves your Mac.")
                    .font(.system(size: 12)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 32, leading: 36, bottom: 28, trailing: 36))
        .frame(width: 480, alignment: .leading)
        .onChange(of: models.selected) { _, s in if s != nil { close() } }
    }
}

/// Photographs a window as it really renders (ImageRenderer cannot draw
/// AppKit-backed controls). Design review and tests.
enum WelcomeSnapshot {
    @MainActor static func capture(window: NSWindow?, to path: String) {
        guard let w = window else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(w.windowNumber), path]
        try? p.run()
        p.waitUntilExit()
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

/// Feed URL override for tests (a local appcast) and a log line when a
/// probe finds an update, so tests/update.sh can see Sparkle work.
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    static let shared = UpdaterDelegate()

    func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["GEIST_FEED_URL"]
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        FileHandle.standardError.write(Data("[geist] update available: \(item.displayVersionString)\n".utf8))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        FileHandle.standardError.write(Data("[geist] no update: \(error.localizedDescription)\n".utf8))
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        FileHandle.standardError.write(Data("[geist] update check failed: \(error.localizedDescription)\n".utf8))
    }
}
