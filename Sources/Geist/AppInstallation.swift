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
    static func version(at url: URL) -> AppVersion? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.geisten.geist",
              let value = info["CFBundleShortVersionString"] as? String else { return nil }
        return AppVersion(value)
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
            guard incoming >= installed else { throw Failure.downgrade }
        }
        let parent = destination.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".Geist-install-\(UUID().uuidString).app")
        let backup = parent.appendingPathComponent(".Geist-previous-\(UUID().uuidString).app")
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
}

@MainActor
enum LaunchInstallation {
    // Test/development bundles never relocate themselves. Distributed DMGs
    // offer one install action; stale mounted copies open the installed app.
    static func prepare() async -> Bool {
        let source = Bundle.main.bundleURL
        guard ProcessInfo.processInfo.environment["GEIST_HOME"] == nil,
              let current = AppInstallation.version(at: source) else { return true }
        let destination = URL(fileURLWithPath: "/Applications/Geist.app", isDirectory: true)
        if source.standardizedFileURL != destination,
           let installed = AppInstallation.version(at: destination), installed >= current {
            await openInstalled(destination)
            return false
        }
        guard source.path.hasPrefix("/Volumes/") || source.path.contains("/AppTranslocation/") else {
            return await closeOtherCopies()
        }
        let alert = NSAlert()
        alert.messageText = desktopText("Install Geist in Applications?")
        alert.informativeText = desktopText("This replaces the previous app. Your models and settings are kept.")
        alert.addButton(withTitle: desktopText("Install and open"))
        alert.addButton(withTitle: desktopText("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        do {
            // GUI copies are closed before the replacement. The service keeps
            // working until the newly installed CLI performs its version handoff.
            guard await closeOtherCopies() else { return false }
            try AppInstallation.replace(source: source, destination: destination, prepare: {})
            await openInstalled(destination)
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = desktopText("Geist could not be installed")
            errorAlert.informativeText = desktopText("The previous app is kept. Copy Geist to Applications in Finder, then open it there.")
            errorAlert.runModal()
            NSWorkspace.shared.activateFileViewerSelecting([source])
        }
        return false
    }
    private static func openInstalled(_ url: URL) async {
        do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
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
        alert.messageText = desktopText("Close the previous Geist app first")
        alert.informativeText = desktopText("An update or another window is still open. Your model service has not been stopped.")
        alert.runModal()
        return false
    }
}
