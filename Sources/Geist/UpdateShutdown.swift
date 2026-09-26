import Foundation

// Sparkle checks mayInstall again when its postponed installation resumes.
// A failed service stop must abort that installation, not merely log an error.
@MainActor
final class UpdateShutdown {
    enum State { case idle, stopping, ready, failed }
    private(set) var state: State = .idle
    private var generation = 0

    var mayInstall: Bool { state == .idle || state == .ready }

    func prepare(stop: @escaping @Sendable () -> Bool,
                 completion: @escaping @MainActor (Bool) -> Void) {
        guard state == .idle else { return }
        state = .stopping
        generation += 1
        let attempt = generation
        Task {
            let stopped = await Task.detached(operation: stop).value
            // A cancelled update cycle must never resume an obsolete installer.
            guard attempt == generation else { return }
            state = stopped ? .ready : .failed
            completion(stopped)
        }
    }

    func reset() {
        generation += 1
        state = .idle
    }
}
