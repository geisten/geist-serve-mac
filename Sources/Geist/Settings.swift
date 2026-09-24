// Settings — login item, network exposure, command line tool.
import AppKit
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class Settings {
    enum CLI: Equatable {
        case none                 // no geist-serve on PATH, no symlink
        case homebrew(String)     // brew owns it: leave it alone
        case installed            // our symlink, pointing into this bundle
        case stale(String)        // our symlink, pointing somewhere else (app moved)
    }

    private(set) var launchAtLogin = false
    private(set) var networkReachable = false
    private(set) var cli: CLI = .none

    @ObservationIgnored private let defaults: UserDefaults =
        ProcessInfo.processInfo.environment["GEIST_HOME"] != nil
            ? UserDefaults(suiteName: "com.geisten.geist.test")! : .standard
    /// Where the symlink goes; tests point this at a temp dir.
    @ObservationIgnored private let cliDir =
        ProcessInfo.processInfo.environment["GEIST_CLI_DIR"] ?? "/usr/local/bin"

    init() {
        networkReachable = defaults.bool(forKey: "network")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshCLI()
    }

    var host: String { networkReachable ? "0.0.0.0" : "127.0.0.1" }

    // MARK: - Login item

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log("login item: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Ollama's behaviour: once a model is chosen, the app comes back at
    /// login without asking. Done once; the user can switch it off.
    func enableLaunchAtLoginOnce() {
        guard !defaults.bool(forKey: "loginItemOffered") else { return }
        defaults.set(true, forKey: "loginItemOffered")
        if ProcessInfo.processInfo.environment["GEIST_HOME"] != nil { return } // never from tests
        setLaunchAtLogin(true)
    }

    // MARK: - Network

    func setNetworkReachable(_ on: Bool) {
        networkReachable = on
        defaults.set(on, forKey: "network")
    }

    // MARK: - Command line tool

    static var bundledServer: URL { ServerProcess.serverBinary.standardizedFileURL }
    var linkPath: String { cliDir + "/geist-serve" }

    func refreshCLI() {
        let fm = FileManager.default
        // 1. Something on PATH that is not our link?
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        for dir in path.split(separator: ":") {
            let candidate = String(dir) + "/geist-serve"
            guard candidate != linkPath, fm.isExecutableFile(atPath: candidate) else { continue }
            let real = (try? fm.destinationOfSymbolicLink(atPath: candidate)).map { URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: candidate)).standardizedFileURL.path } ?? candidate
            if real.contains("/Cellar/") || real.hasPrefix("/opt/homebrew/") || real.contains("/linuxbrew/") {
                cli = .homebrew(candidate)
                log("cli: homebrew at \(candidate)")
                return
            }
        }
        // 2. Our link?
        if let dest = try? fm.destinationOfSymbolicLink(atPath: linkPath) {
            let target = URL(fileURLWithPath: dest).standardizedFileURL
            cli = target == Self.bundledServer ? .installed : .stale(target.path)
        } else {
            cli = .none
        }
        log("cli: \(cli)")
    }

    /// Symlink /usr/local/bin/geist-serve → the bundled binary. Direct when
    /// the directory is writable, else through the admin dialog (what
    /// Ollama does).
    func installCLI() {
        let fm = FileManager.default
        let target = Self.bundledServer.path
        if fm.isWritableFile(atPath: cliDir) || (!fm.fileExists(atPath: cliDir) && fm.isWritableFile(atPath: (cliDir as NSString).deletingLastPathComponent)) {
            try? fm.createDirectory(atPath: cliDir, withIntermediateDirectories: true)
            try? fm.removeItem(atPath: linkPath)
            do { try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: target) }
            catch { log("cli: \(error.localizedDescription)") }
        } else {
            let sh = "mkdir -p '\(cliDir)' && ln -sfn '\(target)' '\(linkPath)'"
            let script = "do shell script \"\(sh.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            if let err { log("cli: \(err[NSAppleScript.errorMessage] ?? "admin dialog cancelled")") }
        }
        refreshCLI()
    }

    private func log(_ s: String) {
        FileHandle.standardError.write(Data("[geist] \(s)\n".utf8))
    }
}
