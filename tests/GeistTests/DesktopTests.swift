import AppKit
import Darwin
import WebKit
import XCTest
@testable import Geist

final class DesktopPolicyTests: XCTestCase {
    func testPrivateOriginAndExternalNavigation() {
        let origin = URL(string: "http://127.0.0.1:18766/#" + String(repeating: "a", count: 64))!
        XCTAssertTrue(DesktopPolicy.local(origin, origin: origin))
        for value in ["http://127.0.0.1:18767/", "https://127.0.0.1:18766/", "http://localhost:18766/", "file:///tmp/test", "http://user@127.0.0.1:18766/"] {
            XCTAssertFalse(DesktopPolicy.local(URL(string: value), origin: origin), value)
        }
        XCTAssertTrue(DesktopPolicy.external(URL(string: "https://github.com/geisten/geist-home-assistant")!))
        for value in ["javascript:alert(1)", "https://example.org/", "https://github.com/geisten/repo#private", "https://github.com/geisten-other/repo"] {
            XCTAssertFalse(DesktopPolicy.external(URL(string: value)!))
        }
        XCTAssertTrue(DesktopPolicy.validKey(String(repeating: "a", count: 64)))
        XCTAssertFalse(DesktopPolicy.validKey(String(repeating: "g", count: 64)))
        XCTAssertFalse(DesktopPolicy.validKey(String(repeating: "a", count: 63)))
    }
}

@MainActor
final class DesktopWebViewTests: XCTestCase {
    func evaluate(_ view: WKWebView, _ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            view.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value) }
            }
        }
    }
    func waitFor(_ view: WKWebView, _ condition: String, timeout: Int = 200) async throws {
        for _ in 0..<timeout {
            if let value = try? await evaluate(view, condition), value as? Bool == true { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(domain: "DesktopTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebView condition did not become true: \(condition)"])
    }
    func confirm(_ desktop: DesktopWindow, element: String, accept: Bool) async throws {
        let click = Task { try await evaluate(desktop.webView, "document.getElementById('\(element)').click(); true") }
        for _ in 0..<100 {
            if desktop.window?.attachedSheet != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let content = desktop.window?.attachedSheet?.contentView else {
            throw NSError(domain: "DesktopTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing native confirmation"])
        }
        func buttons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        guard let button = buttons(content).first(where: { accept ? $0.title == "OK" : ["Cancel", "Abbrechen"].contains($0.title) }) else {
            throw NSError(domain: "DesktopTest", code: 3)
        }
        button.performClick(nil)
        _ = try await click.value
    }
    func snapshot(_ view: WKWebView, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["GEIST_DESKTOP_EVIDENCE"] else { return }
        let picture: NSImage = try await withCheckedThrowingContinuation { continuation in
            view.takeSnapshot(with: nil) { picture, error in
                if let error { continuation.resume(throwing: error) }
                else if let picture { continuation.resume(returning: picture) }
                else { continuation.resume(throwing: NSError(domain: "Snapshot", code: 1)) }
            }
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let image = picture.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Snapshot", code: 2)
        }
        try data.write(to: folder.appendingPathComponent(name))
    }
    func testActualLocalInterfaceInPrivateNativeWindow() async throws {
        guard let runtime = ProcessInfo.processInfo.environment["GEIST_DESKTOP_RUNTIME"] else {
            throw XCTSkip("Set GEIST_DESKTOP_RUNTIME to test the real C23 service in WKWebView")
        }
        _ = NSApplication.shared
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let model = ProcessInfo.processInfo.environment["GEIST_TEST_MODEL"]
        if let model {
            let models = home.appendingPathComponent("models")
            try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: model), to: models.appendingPathComponent("smollm2-360m-instruct-q8_0.gguf"))
        }
        let previousLanguage = UserDefaults.standard.object(forKey: "interfaceLanguage")
        defer {
            if let previousLanguage { UserDefaults.standard.set(previousLanguage, forKey: "interfaceLanguage") }
            else { UserDefaults.standard.removeObject(forKey: "interfaceLanguage") }
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: runtime).appendingPathComponent("geist-app")
        child.arguments = ["--home", home.path, "--port", "0", "--daemon", model == nil ? "/usr/bin/false" : URL(fileURLWithPath: runtime).appendingPathComponent("geistd").path]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let descriptor = home.appendingPathComponent("connection.json")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: descriptor.path) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: descriptor)) as! [String: Any]
        let url = URL(string: "http://127.0.0.1:\(data["port"]!)/#\(data["api_key"]!)")!
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        let desktop = DesktopWindow(clipboard: clipboard, retry: {})
        defer { desktop.close() }
        desktop.update(url: url, status: "Starting…", working: false)
        desktop.present()
        XCTAssertTrue(desktop.window!.isVisible)
        XCTAssertFalse(desktop.webView.configuration.websiteDataStore.isPersistent)
        try await waitFor(desktop.webView, "document.querySelectorAll('.model').length === 6")
        try await waitFor(desktop.webView, "tasks.length === 5 && selectedTask?.id === 'freeform'")
        desktop.window?.appearance = NSAppearance(named: .aqua)
        try await waitFor(desktop.webView, "!matchMedia('(prefers-color-scheme: dark)').matches")
        try await snapshot(desktop.webView, name: "setup-light.png")
        desktop.window?.appearance = NSAppearance(named: .darkAqua)
        try await waitFor(desktop.webView, "matchMedia('(prefers-color-scheme: dark)').matches")
        try await snapshot(desktop.webView, name: "setup-dark.png")
        desktop.window?.appearance = NSAppearance(named: .aqua)
        let initial = try await evaluate(desktop.webView, "document.getElementById('workspace').hidden && !document.getElementById('setup').hidden && state.models.every(m => !m.preview_accepted)")
        XCTAssertEqual(initial as? Bool, true, "Preview requires deliberate setup action")
        _ = try await evaluate(desktop.webView, "document.querySelector('[data-page=\"test-page\"]').click(); true")
        let testVisible = try await evaluate(desktop.webView, "!document.getElementById('test-page').hidden")
        XCTAssertEqual(testVisible as? Bool, true)
        _ = try await evaluate(desktop.webView, "document.getElementById('prompt').value = 'Keep my input'; document.getElementById('ui-language').value = 'de'; document.getElementById('ui-language').dispatchEvent(new Event('change')); true")
        let heading = try await evaluate(desktop.webView, "document.getElementById('task-title').textContent")
        XCTAssertEqual(heading as? String, "Was möchtest du ausprobieren?")
        let retained = try await evaluate(desktop.webView, "document.getElementById('prompt').value")
        XCTAssertEqual(retained as? String, "Keep my input")
        _ = try await evaluate(desktop.webView, "document.getElementById('ui-language').value = 'en'; document.getElementById('ui-language').dispatchEvent(new Event('change')); true")
        desktop.window?.setContentSize(NSSize(width: 540, height: 600))
        try await Task.sleep(nanoseconds: 200_000_000)
        let fits = try await evaluate(desktop.webView, "document.documentElement.scrollWidth <= innerWidth")
        XCTAssertEqual(fits as? Bool, true)
        try await snapshot(desktop.webView, name: "test-narrow.png")
        _ = try await evaluate(desktop.webView, "window.copyDone=false; copyText('Desktop clipboard check').then(() => window.copyDone=true); true")
        try await waitFor(desktop.webView, "window.copyDone")
        XCTAssertEqual(clipboard.string(forType: .string), "Desktop clipboard check")
        if model != nil {
            _ = try await evaluate(desktop.webView, "document.querySelector('[data-id=\"smollm2-360m\"] button').click(); document.getElementById('setup-start').click(); true")
            try await waitFor(desktop.webView, "state?.ready === true && !document.getElementById('workspace').hidden", timeout: 600)
            let inputVisible = try await evaluate(desktop.webView, "document.getElementById('run').getBoundingClientRect().bottom < innerHeight")
            XCTAssertEqual(inputVisible as? Bool, true, "Input and primary action fit a narrow window")
            _ = try await evaluate(desktop.webView, "document.querySelector('[data-task=ideas]').click(); true")
            let sameModel = try await evaluate(desktop.webView, "selectedTask.id === 'ideas' && state.active_id === 'smollm2-360m' && !state.busy")
            XCTAssertEqual(sameModel as? Bool, true)
            _ = try await evaluate(desktop.webView, "document.querySelector('[data-task=ideas]').click(); true")
            try await snapshot(desktop.webView, name: "ready-narrow.png")
            _ = try await evaluate(desktop.webView, "document.getElementById('prompt').value='Say hello in one short sentence.'; document.getElementById('task-form').requestSubmit(); true")
            try await waitFor(desktop.webView, "document.getElementById('output').textContent.length > 0 && controller === null", timeout: 900)
            try await snapshot(desktop.webView, name: "real-response.png")
            let realTokens = try await evaluate(desktop.webView, "document.getElementById('speed').textContent")
            XCTAssertFalse((realTokens as? String ?? "—").contains("—"), "A real response must include final generation metrics")
            try await waitFor(desktop.webView, "!document.getElementById('test-connection').disabled")
            _ = try await evaluate(desktop.webView, "document.querySelector('[data-page=\"connect-page\"]').click(); document.getElementById('test-connection').click(); true")
            try await waitFor(desktop.webView, "!connectionTesting && document.getElementById('connection-result').textContent.startsWith('Connected.')", timeout: 600)
            _ = try await evaluate(desktop.webView, "document.getElementById('language-choice').value='de'; document.getElementById('language-choice').dispatchEvent(new Event('change')); document.getElementById('ui-language').value='de'; document.getElementById('ui-language').dispatchEvent(new Event('change')); true")
            try await waitFor(desktop.webView, "state?.answer_language === 'de' && document.documentElement.lang === 'de'")
            _ = try await evaluate(desktop.webView, "window.beforeReload = true")
            desktop.webView.reload()
            try await waitFor(desktop.webView, "typeof window.beforeReload === 'undefined' && typeof state !== 'undefined' && state?.ready && selectedTask?.id === 'freeform' && !document.getElementById('workspace').hidden && !document.getElementById('run').disabled")
            let restored = try await evaluate(desktop.webView, "document.documentElement.lang === 'de' && document.getElementById('language-choice').value === 'de' && document.getElementById('prompt').value === ''")
            XCTAssertEqual(restored as? Bool, true, "Preferences and consent persist, prompts do not")
            try await snapshot(desktop.webView, name: "ready-german.png")
            _ = try await evaluate(desktop.webView, "api('/app/connections').then(response => response.json()).then(c => window.testDaemonPID=c.daemon_pid); true")
            try await waitFor(desktop.webView, "window.testDaemonPID > 0")
            let daemon = try await evaluate(desktop.webView, "window.testDaemonPID") as! Int
            XCTAssertEqual(kill(pid_t(daemon), SIGKILL), 0)
            try await waitFor(desktop.webView, "state && !state.ready && !state.loading")
            _ = try await evaluate(desktop.webView, "document.querySelector('[data-page=\"models-page\"]').click(); document.querySelector('[data-id=\"smollm2-360m\"] .remove').id='remove-test'; true")
            let removable = try await evaluate(desktop.webView, "!document.getElementById('remove-test').disabled")
            XCTAssertEqual(removable as? Bool, true, "An exited model must remain removable")
            try await confirm(desktop, element: "remove-test", accept: true)
            try await waitFor(desktop.webView, "state.models.find(model => model.id === 'smollm2-360m').installed === false")
            XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("models/smollm2-360m-instruct-q8_0.gguf").path))
        }
        try await confirm(desktop, element: "quit", accept: false)
        XCTAssertTrue(child.isRunning, "Cancelling the native confirmation preserves the service")
        desktop.close()
        XCTAssertTrue(child.isRunning, "Closing the window must preserve the shared service")
        desktop.present()
        XCTAssertTrue(desktop.window!.isVisible)
        try await confirm(desktop, element: "quit", accept: true)
        for _ in 0..<100 {
            if !child.isRunning { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(child.isRunning, "Explicit confirmed service stop must reach the supervisor")
        desktop.update(url: nil, status: "Local service stopped", working: false)
        XCTAssertTrue(desktop.webView.isHidden)
    }
}
