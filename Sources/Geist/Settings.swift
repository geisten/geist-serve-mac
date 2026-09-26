// Only operating-system integration belongs in this native shell.
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class Settings {
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            FileHandle.standardError.write(Data("Geist login item: \(error.localizedDescription)\n".utf8))
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
