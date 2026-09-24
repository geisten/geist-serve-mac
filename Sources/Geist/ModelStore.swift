// ModelStore — where the selected GGUF is remembered. Issue #3 grows this
// into the curated list with downloads; for now it is the file the user
// picked, or GEIST_MODEL for development and tests.
import AppKit
import Foundation

enum ModelStore {
    private static let key = "modelPath"

    static var selectedModel: URL? {
        if let env = ProcessInfo.processInfo.environment["GEIST_MODEL"] { return URL(fileURLWithPath: env) }
        guard let p = UserDefaults.standard.string(forKey: key), FileManager.default.fileExists(atPath: p)
        else { return nil }
        return URL(fileURLWithPath: p)
    }

    @MainActor
    static func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a GGUF model"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, url.pathExtension == "gguf" else { return nil }
        UserDefaults.standard.set(url.path, forKey: key)
        return url
    }
}
