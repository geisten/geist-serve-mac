import AppKit

struct AppVersion: Comparable {
    let numbers: [Int]
    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        numbers = parts.map { Int($0)! }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
}

// Only the application bundle is replaced. Models, preferences and keys live
// outside it. Staging and rollback stay on the destination filesystem.
enum AppInstallation {
    enum Failure: Error { case invalidBundle, downgrade, unsafeDestination }
    private static func info(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }
    static func version(at url: URL) -> AppVersion? {
        guard let info = info(at: url), info["CFBundleIdentifier"] as? String == "com.geisten.geist",
              let value = info["CFBundleShortVersionString"] as? String else { return nil }
        return AppVersion(value)
    }
    static func build(at url: URL) -> Int {
        (info(at: url)?["CFBundleVersion"] as? String).flatMap { Int($0) } ?? 0
    }
    /// Version, then build number: is `a` at least as new as `b`?
    private static func atLeast(_ a: URL, _ av: AppVersion, _ b: URL, _ bv: AppVersion) -> Bool {
        av > bv || (av == bv && build(at: a) >= build(at: b))
    }
    static func isAtLeastAsNew(_ installed: URL, as incoming: URL) -> Bool {
        guard let a = version(at: installed), let b = version(at: incoming) else { return false }
        return atLeast(installed, a, incoming, b)
    }
    static func verify(_ bundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", bundle.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.invalidBundle }
    }
    static func replace(source: URL, destination: URL,
                        verify: (URL) throws -> Void = verify,
                        prepare: () throws -> Void) throws {
        let fm = FileManager.default
        guard let incoming = version(at: source) else { throw Failure.invalidBundle }
        let exists = fm.fileExists(atPath: destination.path)
        if (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw Failure.unsafeDestination
        }
        if exists {
            guard let installed = version(at: destination) else { throw Failure.invalidBundle }
            guard atLeast(source, incoming, destination, installed) else { throw Failure.downgrade }
        }
        let parent = destination.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".geisten-install-\(UUID().uuidString).app")
        let backup = parent.appendingPathComponent(".geisten-previous-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: source, to: stage)
        try verify(stage)
        try prepare() // Never disturb the running version before copy/validation succeeds.
        if exists { try fm.moveItem(at: destination, to: backup) }
        do { try fm.moveItem(at: stage, to: destination) }
        catch {
            if exists { try fm.moveItem(at: backup, to: destination) }
            throw error
        }
        // Leave the backup in place if cleanup fails, rather than lose the new app.
        if exists { try? fm.removeItem(at: backup) }
    }
    /// The app's bundle name before the rename to geisten (#92).
    static let previousName = "Geist.app"
    /// After an install as geisten.app, a copy under the earlier name is retired, so
    /// one bundle ID never has two installed apps. Only our own, non-symlinked bundle.
    static func retirePrevious(_ previous: URL,
                               retire: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        guard (try? previous.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              version(at: previous) != nil else { return }
        try? retire(previous)
    }
}

@MainActor
enum LaunchInstallation {
    // Test/development bundles never relocate themselves. Distributed DMGs
    // offer one install action; stale mounted copies open the installed app.
    static func prepare() async -> Bool {
        let source = Bundle.main.bundleURL
        guard ProcessInfo.processInfo.environment["GEIST_HOME"] == nil,
              AppInstallation.version(at: source) != nil else { return true }
        let destination = URL(fileURLWithPath: "/Applications/geisten.app", isDirectory: true)
        if source.standardizedFileURL != destination,
           AppInstallation.isAtLeastAsNew(destination, as: source) {
            await openInstalled(destination)
            return false
        }
        guard source.path.hasPrefix("/Volumes/") || source.path.contains("/AppTranslocation/") else {
            return await closeOtherCopies()
        }
        let alert = NSAlert()
        alert.messageText = desktopText("Install geisten in Applications?")
        alert.informativeText = desktopText("This replaces the previous app. Your models and settings are kept.")
        alert.addButton(withTitle: desktopText("Install and open"))
        alert.addButton(withTitle: desktopText("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        do {
            // GUI copies are closed before the replacement. The service keeps
            // working until the newly installed CLI performs its version handoff.
            guard await closeOtherCopies() else { return false }
            try AppInstallation.replace(source: source, destination: destination, prepare: {})
            AppInstallation.retirePrevious(destination.deletingLastPathComponent()
                .appendingPathComponent(AppInstallation.previousName))
            await openInstalled(destination)
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = desktopText("geisten could not be installed")
            errorAlert.informativeText = desktopText("The previous app is kept. Copy geisten to Applications in Finder, then open it there.")
            errorAlert.runModal()
            NSWorkspace.shared.activateFileViewerSelecting([source])
        }
        return false
    }
    private static func openInstalled(_ url: URL) async {
        do {
            // Both bundles have the same identifier. Reusing an existing
            // instance would return this DMG installer, which then exits.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        catch {
            let alert = NSAlert(error: error); alert.runModal()
        }
    }
    private static func closeOtherCopies() async -> Bool {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.geisten.geist")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        for app in others { _ = app.terminate() }
        for _ in 0..<50 {
            if others.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let alert = NSAlert()
        alert.messageText = desktopText("Close the previous geisten app first")
        alert.informativeText = desktopText("An update or another window is still open. Your model service has not been stopped.")
        alert.runModal()
        return false
    }
}
