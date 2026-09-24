// ModelStore — which GGUF is selected, which curated ones are on disk,
// and downloads with progress and SHA-256 verification.
//
// Files live in ~/Library/Application Support/Geist/models (GEIST_HOME
// overrides the base for tests). A download goes to <file>.part and is
// renamed only after its hash matches; a mismatch deletes it and is shown.
// ponytail: no resume across launches; a .part left behind is restarted.
import AppKit
import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class ModelStore: NSObject {
    /// Fraction 0…1 while a curated model downloads.
    private(set) var progress: [String: Double] = [:]
    private(set) var lastError: String?
    /// Selected model (curated id or a custom path), as a file URL.
    private(set) var selected: URL?
    /// User-added GGUFs (paths), remembered.
    private(set) var custom: [URL] = []

    /// Called after a download finished and verified, with the file.
    var onReady: ((URL) -> Void)?

    /// Under GEIST_HOME (tests, dev) settings go to their own suite, so a
    /// test run never edits the user's real selection.
    @ObservationIgnored private let defaults: UserDefaults =
        ProcessInfo.processInfo.environment["GEIST_HOME"] != nil
            ? UserDefaults(suiteName: "com.geisten.geist.test")! : .standard
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var session: URLSession!
    /// Base URL override for tests: `<base>/<file>` instead of HuggingFace.
    @ObservationIgnored private let baseOverride = ProcessInfo.processInfo.environment["GEIST_MODEL_BASE_URL"].flatMap(URL.init(string:))

    static let dir: URL = {
        let base = ProcessInfo.processInfo.environment["GEIST_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Geist")
        let d = base.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        custom = (defaults.stringArray(forKey: "customModels") ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if let env = ProcessInfo.processInfo.environment["GEIST_MODEL"] {
            selected = URL(fileURLWithPath: env)
        } else if let p = defaults.string(forKey: "selectedModel"), FileManager.default.fileExists(atPath: p) {
            selected = URL(fileURLWithPath: p)
        }
        // A .part from an interrupted run is neither usable nor resumable.
        for f in (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        where f.pathExtension == "part" { try? FileManager.default.removeItem(at: f) }
    }

    // MARK: - Queries

    func path(_ m: CuratedModel) -> URL { Self.dir.appendingPathComponent(m.file) }
    func isPresent(_ m: CuratedModel) -> Bool { FileManager.default.fileExists(atPath: path(m).path) }
    func isSelected(_ url: URL) -> Bool { selected?.standardizedFileURL == url.standardizedFileURL }
    func isDownloading(_ m: CuratedModel) -> Bool { progress[m.id] != nil }

    // MARK: - Selection

    func select(_ url: URL) {
        selected = url
        defaults.set(url.path, forKey: "selectedModel")
    }

    func addCustom() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a GGUF model"
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, url.pathExtension == "gguf" else { return nil }
        if !custom.contains(url) {
            custom.append(url)
            defaults.set(custom.map(\.path), forKey: "customModels")
        }
        select(url)
        return url
    }

    // MARK: - Download

    func download(_ m: CuratedModel) {
        guard tasks[m.id] == nil else { return }
        lastError = nil
        let url = baseOverride.map { $0.appendingPathComponent(m.url.lastPathComponent) } ?? m.url
        let task = session.downloadTask(with: url)
        task.taskDescription = m.id
        tasks[m.id] = task
        progress[m.id] = 0
        task.resume()
    }

    func cancel(_ m: CuratedModel) {
        tasks[m.id]?.cancel()
        tasks[m.id] = nil
        progress[m.id] = nil
    }

    private func fail(_ msg: String) {
        lastError = msg
        FileHandle.standardError.write(Data("[geist] models: \(msg)\n".utf8))
    }

    private func finished(_ id: String, tmp: URL?, error: Error?) {
        tasks[id] = nil
        progress[id] = nil
        guard let m = Models.byID(id) else { return }
        if let error { fail("\(m.name): \(error.localizedDescription)"); return }
        guard let tmp else { return }
        let part = path(m).appendingPathExtension("part")
        do {
            try? FileManager.default.removeItem(at: part)
            try FileManager.default.moveItem(at: tmp, to: part)
            let have = try Self.sha256(of: part)
            guard have == m.sha256 else {
                try? FileManager.default.removeItem(at: part)
                fail("\(m.name): checksum mismatch, file discarded")
                return
            }
            try? FileManager.default.removeItem(at: path(m))
            try FileManager.default.moveItem(at: part, to: path(m))
        } catch {
            fail("\(m.name): \(error.localizedDescription)")
            return
        }
        FileHandle.standardError.write(Data("[geist] models: \(m.name) downloaded and verified\n".utf8))
        select(path(m))
        onReady?(path(m))
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        var h = SHA256()
        while let chunk = try fh.read(upToCount: 8 << 20), !chunk.isEmpty { h.update(data: chunk) }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ModelStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite
            : (Models.byID(id)?.bytes ?? 1)
        let frac = Double(totalBytesWritten) / Double(expected)
        Task { @MainActor in if self.progress[id] != nil { self.progress[id] = min(frac, 0.999) } }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        // `location` is deleted when this returns: move it somewhere we own first.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("geist-\(id)-\(UUID().uuidString)")
        try? FileManager.default.moveItem(at: location, to: keep)
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        Task { @MainActor in
            if status == 200 { self.finished(id, tmp: keep, error: nil) }
            else {
                try? FileManager.default.removeItem(at: keep)
                self.fail("\(id): HTTP \(status) from \(downloadTask.originalRequest?.url?.absoluteString ?? "?")")
                self.finished(id, tmp: nil, error: URLError(.badServerResponse))
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        if (error as? URLError)?.code == .cancelled { return }
        Task { @MainActor in self.finished(id, tmp: nil, error: error) }
    }
}
