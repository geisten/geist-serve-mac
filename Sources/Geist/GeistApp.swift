// Geist — the menu bar app around geist-serve. Skeleton (issue #1): a status
// item and Quit. The server process (#2), models (#3), login item and
// switches (#4), Sparkle (#5) land per issue.
import SwiftUI

@main
struct GeistApp: App {
    @State private var status = "not running"

    var body: some Scene {
        MenuBarExtra {
            Text("geist-serve – \(status)")
            Divider()
            Button("Quit Geist") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "waveform.circle")
        }
    }
}
