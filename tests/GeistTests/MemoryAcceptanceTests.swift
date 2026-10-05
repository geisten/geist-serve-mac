import AppKit
import Darwin
import WebKit
import XCTest
@testable import Geist

extension DesktopWebViewTests {
    /// Opt-in physical Apple Silicon acceptance. Never downloads a fixture or
    /// touches the installed app, user models or normal service data directory.
    func testPackagedBonsaiMemoryAcrossCPUAndMetal() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let runtime = environment["GEIST_DESKTOP_RUNTIME"],
              let model = environment["GEIST_BONSAI_TEST_MODEL"],
              let evidence = environment["GEIST_DESKTOP_EVIDENCE"] else {
            throw XCTSkip("Set packaged runtime, cached Bonsai model and fresh evidence directory")
        }
        _ = NSApplication.shared
        let files = FileManager.default
        let home = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = URL(fileURLWithPath: evidence, isDirectory: true)
        try files.createDirectory(at: home.appendingPathComponent("models"), withIntermediateDirectories: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: home) }
        let copy = Process()
        copy.executableURL = URL(fileURLWithPath: "/bin/cp")
        copy.arguments = ["-c", model, home.appendingPathComponent("models/Ternary-Bonsai-2-27B-PQ2_0.gguf").path]
        try copy.run(); copy.waitUntilExit()
        XCTAssertEqual(copy.terminationStatus, 0)
        try "cpu".write(to: home.appendingPathComponent("backend-3907dc1658db1f78a9826bf8d5bcb8dc65db0d466388937af57f2294fae62ec1"), atomically: true, encoding: .utf8)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: runtime).appendingPathComponent("geist-app")
        child.arguments = ["--home", home.path, "--port", "0", "--daemon", URL(fileURLWithPath: runtime).appendingPathComponent("geistd").path]
        child.standardOutput = FileHandle.nullDevice
        let log = folder.appendingPathComponent("bonsai-native-runtime.log")
        guard !files.fileExists(atPath: log.path) else {
            XCTFail("Use a fresh evidence directory; earlier results must be preserved")
            return
        }
        files.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        child.standardError = handle
        try child.run()
        defer {
            if child.isRunning { child.terminate(); child.waitUntilExit() }
            try? handle.close()
        }
        let descriptor = home.appendingPathComponent("connection.json")
        for _ in 0..<100 {
            if files.fileExists(atPath: descriptor.path) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let connection = try JSONSerialization.jsonObject(with: Data(contentsOf: descriptor)) as! [String: Any]
        let origin = URL(string: "http://127.0.0.1:\(connection["port"]!)/#\(connection["api_key"]!)")!
        let desktop = DesktopWindow(retry: {})
        defer { desktop.close() }
        desktop.update(url: origin, status: "Starting…", working: false)
        desktop.present()
        desktop.window?.setContentSize(NSSize(width: 900, height: 680))
        try await waitFor(desktop.webView, "typeof state!=='undefined' && state?.models.some(m=>m.id==='bonsai2-27b-pq2' && m.installed)")
        _ = try await evaluate(desktop.webView, "window.memoryTestRenderError=null; window.actualMemoryRender=render; render=function(next){try{return window.actualMemoryRender(next);}catch(error){window.memoryTestRenderError={message:error.message,stack:error.stack};throw error;}}; choose('bonsai2-27b-pq2'); true")
        var pids: [pid_t] = []
        for (index, mode) in ["cpu", "gpu", "cpu"].enumerated() {
            try await waitFor(desktop.webView, "state?.ready && !requesting && !state.busy", timeout: 6000)
            _ = try await evaluate(desktop.webView, "document.querySelector('[name=execution][value=\(mode)]').click(); true")
            try await waitFor(desktop.webView, "state?.ready && !requesting && !state.busy && state.execution.active==='\(mode)'", timeout: 6000)
            let pid = try await evaluate(desktop.webView, "state.lifecycle.pid") as! Int
            if let previous = pids.last, previous != pid_t(pid) {
                XCTAssertNotEqual(kill(previous, 0), 0, "Previous owned runtime must be reaped")
            }
            pids.append(pid_t(pid))
            for stage in ["ready", "reply"] {
                if stage == "reply" {
                    _ = try await evaluate(desktop.webView, "document.getElementById('prompt').value='Reply with exactly OK.'; document.getElementById('task-form').requestSubmit(); true")
                    try await waitFor(desktop.webView, "(poll(), !!state && !controller && !state.inference_busy && document.querySelectorAll('.reply-metrics').length===\(index+1) && [...document.querySelectorAll('.reply-metrics')].at(-1).replyMetrics?.tokens>0)", timeout: 6000)
                }
                try await waitFor(desktop.webView, "state.memory.process_rss_bytes>0 && state.memory.status===\(mode == "gpu" ? 1 : 2)")
                let scoped = try await evaluate(desktop.webView, "state.memory.total_unique_physical_bytes===null && \(mode == "gpu" ? "state.memory.gpu_allocated_bytes>0 && state.memory.gpu_source==='metal.MTLDevice.currentAllocatedSize' && document.getElementById('test-gpu-memory').textContent!=='—'" : "state.memory.gpu_allocated_bytes===null && document.getElementById('test-gpu-memory').textContent==='—'")")
                XCTAssertEqual(scoped as? Bool, true, "The actual loaded backend must retain distinct memory scopes")
                let values = try await evaluate(desktop.webView, "JSON.stringify({memory:state.memory,lifecycle:state.lifecycle,backend:state.execution.active})") as! String
                try values.write(to: folder.appendingPathComponent("bonsai-\(index)-\(mode)-\(stage).json"), atomically: true, encoding: .utf8)
                try await snapshot(desktop.webView, name: "bonsai-\(index)-\(mode)-\(stage).png")
            }
        }
        let renderError = try await evaluate(desktop.webView, "window.memoryTestRenderError")
        XCTAssertTrue(renderError == nil || renderError is NSNull, "Real requests must not lose UI state through rendering errors")
        _ = try await evaluate(desktop.webView, "api('/app/stop',{}).then(()=>poll()); true")
        try await waitFor(desktop.webView, "!state.ready && !state.lifecycle.pid && state.memory.process_rss_bytes===null && state.memory.gpu_allocated_bytes===null")
        for pid in pids { XCTAssertNotEqual(kill(pid, 0), 0) }
        _ = try await evaluate(desktop.webView, "stopped=true; clearInterval(timer); api('/app/quit',{}).catch(()=>{}); true")
        for _ in 0..<100 {
            if !child.isRunning { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(child.isRunning)
    }
}
