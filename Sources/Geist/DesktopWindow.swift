import AppKit
import WebKit

// Shared UI messages are deliberately limited to preferences and clipboard text.
// No message can execute a command, access files or control the model service.
enum DesktopPolicy {
    static func validKey(_ key: String) -> Bool {
        key.utf8.count == 64 && key.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func local(_ candidate: URL?, origin: URL?) -> Bool {
        guard let candidate, let origin else { return false }
        return candidate.scheme == "http" && candidate.host == "127.0.0.1"
            && candidate.port == origin.port && candidate.path == "/" && candidate.user == nil && candidate.password == nil
    }
    static func external(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/geisten/")
            && url.user == nil && url.password == nil && url.fragment == nil
    }
}

@MainActor func desktopText(_ english: String) -> String {
    let language = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? Locale.preferredLanguages.first ?? "en"
    guard language.hasPrefix("de") else { return english }
    return ["Start Geist": "Geist starten", "Start at Login": "Bei Anmeldung starten", "Show Data Folder": "Datenordner anzeigen", "Check for Updates…": "Nach Updates suchen…", "Open Geist": "Geist öffnen", "Quit Geist": "Geist beenden", "Cancel": "Abbrechen",
        "Stop model service": "Modelldienst stoppen", "Stop model service?": "Modelldienst stoppen?",
        "Terminal and editor connections will stop too. Downloaded models are kept.": "Auch Terminal und Editoren werden getrennt. Heruntergeladene Modelle bleiben erhalten.",
        "Starting local service…": "Lokaler Dienst wird gestartet…", "Starting…": "Wird gestartet…",
        "Local service running": "Lokaler Dienst läuft", "Local service stopped": "Lokaler Dienst gestoppt",
        "Start / reconnect": "Starten / neu verbinden", "Cannot read service connection": "Dienstverbindung kann nicht gelesen werden",
        "Service unavailable — check port 8766": "Dienst nicht erreichbar. Prüfe, ob Port 8766 bereits belegt ist.",
        "The interface could not be loaded. Try reconnecting.": "Die Oberfläche konnte nicht geladen werden. Bitte neu verbinden.",
        "Closing this window keeps the model service available to your tools.": "Beim Schließen bleibt der Modelldienst für deine Programme verfügbar."
    ][english] ?? english
}

@MainActor
final class DesktopWindow: NSWindowController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply {
    let webView: WKWebView
    private let overlay = NSStackView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton()
    private let retry: () -> Void
    private let clipboard: NSPasteboard
    private(set) var origin: URL?
    private var loaded: URL?

    init(clipboard: NSPasteboard = .general, retry: @escaping () -> Void) {
        self.retry = retry
        self.clipboard = clipboard
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let locale = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? Locale.preferredLanguages.first ?? "en"
        let language = locale.hasPrefix("de") ? "de" : "en"
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.geistLanguage = '\(language)'; window.geistDesktop = 'mac';",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Geist"
        window.minSize = NSSize(width: 540, height: 500)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "desktop")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        let content = NSView()
        window.contentView = content
        webView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(webView)
        overlay.orientation = .vertical
        overlay.spacing = 20
        overlay.alignment = .centerX
        overlay.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 18, weight: .medium)
        statusLabel.alignment = .center
        retryButton.title = desktopText("Start / reconnect")
        retryButton.target = self
        retryButton.action = #selector(reconnect)
        retryButton.bezelStyle = .rounded
        overlay.addArrangedSubview(statusLabel)
        overlay.addArrangedSubview(retryButton)
        let help = NSTextField(wrappingLabelWithString: desktopText("Closing this window keeps the model service available to your tools."))
        help.alignment = .center
        help.textColor = .secondaryLabelColor
        overlay.addArrangedSubview(help)
        content.addSubview(overlay)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: content.topAnchor), webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor), webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            overlay.centerXAnchor.constraint(equalTo: content.centerXAnchor), overlay.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            overlay.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            overlay.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            overlay.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func reconnect() { loaded = nil; retry() }
    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func update(url: URL?, status: String, working: Bool) {
        statusLabel.stringValue = desktopText(status)
        retryButton.isEnabled = !working
        guard let url else {
            origin = nil; loaded = nil; webView.stopLoading()
            webView.isHidden = true; overlay.isHidden = false
            return
        }
        origin = url
        if loaded != url {
            loaded = url
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard DesktopPolicy.local(webView.url, origin: origin) else { return }
        overlay.isHidden = true; webView.isHidden = false
    }
    private func failed() {
        loaded = nil
        statusLabel.stringValue = desktopText("The interface could not be loaded. Try reconnecting.")
        retryButton.isEnabled = true
        webView.isHidden = true; overlay.isHidden = false
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if DesktopPolicy.local(action.request.url, origin: origin) && action.targetFrame?.isMainFrame == true {
            decisionHandler(.allow); return
        }
        if action.navigationType == .linkActivated, DesktopPolicy.local(action.sourceFrame.request.url, origin: origin),
           let url = action.request.url, DesktopPolicy.external(url) { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard frame.isMainFrame, DesktopPolicy.local(frame.request.url, origin: origin), let window else {
            completionHandler(false); return
        }
        let alert = NSAlert()
        alert.messageText = String(message.prefix(2000))
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: desktopText("Cancel"))
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, DesktopPolicy.local(message.frameInfo.request.url, origin: origin),
              let body = message.body as? [String: String] else { replyHandler(nil, "Denied"); return }
        switch body["action"] {
        case "language":
            guard let value = body["value"], ["de", "en"].contains(value) else { replyHandler(nil, "Invalid language"); return }
            UserDefaults.standard.set(value, forKey: "interfaceLanguage")
        case "copy":
            guard let value = body["value"], value.utf8.count <= 131072 else { replyHandler(nil, "Text too large"); return }
            clipboard.clearContents()
            clipboard.setString(value, forType: .string)
        default: replyHandler(nil, "Unknown action"); return
        }
        replyHandler(true, nil)
    }
}
