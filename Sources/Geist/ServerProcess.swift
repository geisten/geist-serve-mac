// ServerProcess — the one geist-serve child this app owns.
//
// States are what the menu shows. A crash restarts once; a second crash
// stays `failed` until the user acts. Port 11434 is fixed because every
// client is configured for it: if something else answers there (Ollama),
// the state says so instead of picking another port.
import Foundation
import Observation

@MainActor
@Observable
final class ServerProcess {
    enum State: Equatable {
        case stopped
        case starting
        case running(model: String)
        case failed(String)
        case portInUse
    }

    private(set) var state: State = .stopped
    private(set) var log: [String] = []
    let port: Int
    var host: String

    private var process: Process?
    private var healthTimer: Timer?
    private var restartedOnce = false
    private var stopping = false
    private var modelURL: URL?
    private let logCap = 500

    init(port: Int = 11434, host: String = "127.0.0.1") {
        self.port = port
        self.host = host
    }

    var isRunning: Bool { if case .running = state { return true } else { return false } }

    var statusText: String {
        switch state {
        case .stopped: return "stopped"
        case .starting: return "starting…"
        case .running(let m): return "running (\(m))"
        case .failed(let why): return "failed: \(why)"
        case .portInUse: return "port \(port) is in use"
        }
    }

    // MARK: - Control

    func start(model: URL) {
        modelURL = model
        restartedOnce = false
        Task { await launch() }
    }

    func stop() {
        stopping = true
        healthTimer?.invalidate()
        healthTimer = nil
        guard let p = process, p.isRunning else {
            state = .stopped
            stopping = false
            return
        }
        p.terminate() // SIGTERM: geist-serve finishes the in-flight response and exits
        let deadline = Date().addingTimeInterval(10)
        while p.isRunning, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        process = nil
        state = .stopped
        stopping = false
        append("[geist] server stopped")
    }

    func restart() {
        guard let m = modelURL else { return }
        stop()
        start(model: m)
    }

    // MARK: - Launch

    private func launch() async {
        guard let model = modelURL else { return }
        if await Self.somethingAnswers(port: port) {
            state = .portInUse
            append("[geist] port \(port) already answers; Ollama running?")
            return
        }
        let p = Process()
        p.executableURL = Self.serverBinary
        p.arguments = [model.path, "--port", String(port), "--host", host]
        var env = ProcessInfo.processInfo.environment
        env["OMP_NUM_THREADS"] = String(Self.performanceCores)
        env["OMP_WAIT_POLICY"] = "active"
        p.environment = env
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.append(text) }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.exited(proc) }
        }
        do {
            try p.run()
        } catch {
            state = .failed("cannot launch geist-serve: \(error.localizedDescription)")
            return
        }
        process = p
        state = .starting
        append("[geist] launched pid \(p.processIdentifier) with \(model.lastPathComponent)")
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    private func exited(_ proc: Process) {
        healthTimer?.invalidate()
        healthTimer = nil
        process = nil
        if stopping { return }
        let why = "exit \(proc.terminationStatus) (\(lastLogLine))"
        append("[geist] server exited unexpectedly: \(why)")
        if !restartedOnce {
            restartedOnce = true
            append("[geist] restarting once")
            Task { await launch() }
        } else {
            state = .failed(why)
        }
    }

    private func poll() async {
        guard let p = process, p.isRunning else { return }
        if await Self.somethingAnswers(port: port, path: "/health") {
            if case .running = state { return }
            state = .running(model: modelURL?.deletingPathExtension().lastPathComponent ?? "?")
            healthTimer?.invalidate()
            healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.poll() }
            }
        }
    }

    // MARK: - Helpers

    private func append(_ text: String) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            log.append(String(line))
            // Our own state lines also go to stderr: Console.app and the
            // integration test read them there.
            if line.hasPrefix("[geist]") { FileHandle.standardError.write(Data((line + "\n").utf8)) }
        }
        if log.count > logCap { log.removeFirst(log.count - logCap) }
    }

    private var lastLogLine: String { log.last(where: { !$0.hasPrefix("[geist]") }) ?? "no output" }

    static var serverBinary: URL {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("geist-serve")
    }

    static var performanceCores: Int {
        var n: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &n, &size, nil, 0) == 0, n > 0 { return Int(n) }
        return max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
    }

    /// True when something HTTP-ish answers on 127.0.0.1:port. Used both
    /// for the pre-start conflict probe (/api/version) and health.
    nonisolated static func somethingAnswers(port: Int, path: String = "/api/version") async -> Bool {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.timeoutInterval = 1.5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Ask a running Ollama.app to quit (what the "port in use" alert offers).
    static func quitOllama() {
        let script = NSAppleScript(source: "tell application \"Ollama\" to quit")
        script?.executeAndReturnError(nil)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-x", "ollama"]
        try? p.run()
        p.waitUntilExit()
    }
}
