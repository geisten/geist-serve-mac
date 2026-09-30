import AppKit
import WebKit
import UniformTypeIdentifiers

// Shared UI messages are deliberately limited to preferences and clipboard text.
// No message can execute a command, access files or control the model service.
enum DesktopPolicy {
    static func initialSize(visible: NSSize) -> NSSize {
        NSSize(width: min(780, max(540, visible.width * 0.72)),
               height: min(620, max(480, visible.height * 0.78)))
    }
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

/// What the local page learns about its host before any of its scripts run.
/// Every interpolated value is an allowlisted token or JSON-encoded.
enum DesktopBootstrap {
    /// The bundled command line tool, wherever this app is installed (#60).
    static var cliPath: String {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("geist-cli").path
    }
    static func script(cliPath: String = cliPath) -> String {
        let quoted = (try? JSONEncoder().encode(cliPath)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        return DesktopLanguage.script + " window.geistCLIPath = \(quoted);"
    }
}

enum DesktopDestination: String {
    case models = "models-page", connect = "connect-page", settings = "settings-page", test = "test-page"
}

@MainActor
final class DesktopWindow: NSWindowController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply {
    let webView: WKWebView
    private let overlay = NSStackView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton()
    private let help = NSTextField(wrappingLabelWithString: "")
    private var statusText = "Starting…"
    private let retry: () -> Void
    private let clipboard: NSPasteboard
    private(set) var origin: URL?
    private var loaded: URL?
    private var navigationReady = false
    private var pendingDestination: DesktopDestination?

    init(clipboard: NSPasteboard = .general, retry: @escaping () -> Void) {
        self.retry = retry
        self.clipboard = clipboard
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.tabFocusesLinks = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: DesktopBootstrap.script(),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        let size = DesktopPolicy.initialSize(visible: NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Geist"
        window.minSize = NSSize(width: 540, height: 480)
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .white
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
        help.stringValue = desktopText("Closing this window keeps the model service available to your tools.")
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
    func present(destination: DesktopDestination? = nil) {
        if let destination { pendingDestination = destination }
        routePendingDestination()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func update(url: URL?, status: String, working: Bool) {
        statusText = status
        statusLabel.stringValue = desktopText(status)
        retryButton.isEnabled = !working
        guard let url else {
            origin = nil; loaded = nil; navigationReady = false; webView.stopLoading()
            webView.isHidden = true; overlay.isHidden = false
            return
        }
        origin = url
        if loaded != url {
            loaded = url; navigationReady = false
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard DesktopPolicy.local(webView.url, origin: origin) else { return }
        overlay.isHidden = true; webView.isHidden = false
        navigationReady = true
        routePendingDestination()
    }
    private func routePendingDestination() {
        guard navigationReady, DesktopPolicy.local(webView.url, origin: origin), let destination = pendingDestination else { return }
        webView.callAsyncJavaScript("return window.geistNavigate?.(page) === true", arguments: ["page": destination.rawValue],
                                   in: nil, in: .page) { [weak self] result in
            if case .success(let applied as Bool) = result, applied, self?.pendingDestination == destination {
                self?.pendingDestination = nil
            }
        }
    }
    private func failed() {
        loaded = nil; navigationReady = false
        statusText = "The interface could not be loaded. Try reconnecting."
        statusLabel.stringValue = desktopText(statusText)
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
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        guard frame.isMainFrame, DesktopPolicy.local(frame.request.url, origin: origin), let window else {
            completionHandler(nil); return
        }
        // Only the file explicitly selected by the owner is exposed to the local page.
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, DesktopPolicy.local(message.frameInfo.request.url, origin: origin),
              let body = message.body as? [String: String] else { replyHandler(nil, "Denied"); return }
        switch body["action"] {
        case "language":
            guard let value = body["value"], ["system", "de", "en"].contains(value) else { replyHandler(nil, "Invalid language"); return }
            UserDefaults.standard.set(value, forKey: "interfaceLanguage")
            retryButton.title = desktopText("Start / reconnect")
            help.stringValue = desktopText("Closing this window keeps the model service available to your tools.")
            statusLabel.stringValue = desktopText(statusText)
            // The same ephemeral WebView can reconnect after a service restart.
            // Future documents must receive the latest bounded preference.
            controller.removeAllUserScripts()
            controller.addUserScript(WKUserScript(
                source: DesktopBootstrap.script(),
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        case "copy":
            guard let value = body["value"], value.utf8.count <= 131072 else { replyHandler(nil, "Text too large"); return }
            clipboard.clearContents()
            clipboard.setString(value, forType: .string)
        default: replyHandler(nil, "Unknown action"); return
        }
        replyHandler(true, nil)
    }
}
