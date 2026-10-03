// Native integration only. Model policy, downloads, hardware detection,
// inference lifecycle and the interface are owned by the C23 geist-app.
import AppKit
import Sparkle
import SwiftUI

@main
struct GeistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage("interfaceLanguage") private var interfacePreference = "system"
    var body: some Scene {
        let _ = interfacePreference // Refresh menu labels when the shared interface preference changes.
        MenuBarExtra("geisten", systemImage: "waveform.circle") {
            Text(desktopText(delegate.runtime.status))
                .onAppear { delegate.runtime.refresh() }
            if !delegate.runtime.modelName.isEmpty { Text(delegate.runtime.modelName) }
            Button(desktopText("Models")) { delegate.runtime.open(destination: .models) }

                .keyboardShortcut("o")
            Button(desktopText("Connect a program")) { delegate.runtime.open(destination: .connect) }
            Button(desktopText("Settings")) { delegate.runtime.open(destination: .settings) }
                .keyboardShortcut(",")
            if !delegate.runtime.running {
                Button(desktopText("Start geisten")) { delegate.runtime.start() }
            }
            Divider()
            Toggle(desktopText("Start at Login"), isOn: Binding(
                get: { delegate.settings.launchAtLogin },
                set: { delegate.settings.setLaunchAtLogin($0) }))
            Button(desktopText("Show Data Folder")) { NSWorkspace.shared.open(delegate.runtime.dataFolder) }
            Button(desktopText("Check for Updates…")) { delegate.updater.updater.checkForUpdates() }
            Divider()
            Button(desktopText("Stop model service")) { delegate.runtime.confirmStop() }
            Button(desktopText("Quit geisten")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    @MainActor let runtime = ApplicationProcess()
    @MainActor let settings = Settings()
    @MainActor let updateShutdown = UpdateShutdown()
    @MainActor lazy var updater = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        MainActor.assumeIsolated { updateShutdown.mayInstall }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            runtime.updateStopping()
            updateShutdown.prepare(stop: { ApplicationProcess.stopForUpdate() }) { stopped in
                if !stopped { self.runtime.updateStopFailed() }
                // Sparkle rechecks updaterShouldRelaunchApplication before
                // resuming. Calling it after failure causes a clean abort.
                installHandler()
            }
        }
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: Error?) {
        MainActor.assumeIsolated { updateShutdown.reset() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            do { try updater.updater.start() } catch {
                FileHandle.standardError.write(Data("geisten update service: \(error.localizedDescription)\n".utf8))
            }
            NSApp.setActivationPolicy(.regular)
            Task { @MainActor in
                guard await LaunchInstallation.prepare() else { NSApp.terminate(nil); return }
                runtime.start()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { runtime.open() }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Quitting during a postponed update must not let Sparkle's helper
        // replace the bundle before the shared service has stopped.
        MainActor.assumeIsolated {
            updateShutdown.mayInstall ? .terminateNow : .terminateCancel
        }
    }
}
