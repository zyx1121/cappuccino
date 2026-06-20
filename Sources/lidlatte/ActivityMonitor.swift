import Foundation

/// Watches Claude Code's on-disk activity (session transcripts under ~/.claude/projects) via
/// FSEvents and exposes a debounced "busy" signal: `isBusy` flips true on any file event and
/// back to false after `idleTimeout` of silence.
///
/// This is a PROXY for "an agent is working": Claude Code appends to its session .jsonl on
/// every turn / tool call, so disk churn ≈ active work. The blind spot: a long inference or a
/// waiting-on-you gap with no writes can read as idle. `idleTimeout` is the safety margin —
/// kept generous (120s) so a model that's thinking isn't mistaken for one that's finished.
/// TODO(detection): tighten with a process + I/O signal (claude pid busy) to close the gap.
@MainActor
final class ActivityMonitor {
    private(set) var isBusy = false
    var onChange: ((Bool) -> Void)?

    private let idleTimeout: TimeInterval
    private let watchedPaths: [String]
    private var stream: FSEventStreamRef?
    private var idleTimer: Timer?
    private let queue = DispatchQueue(label: "dev.zyx.lidlatte.fsevents")

    init(idleTimeout: TimeInterval = 120) {
        self.idleTimeout = idleTimeout
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.watchedPaths = [home + "/.claude/projects"]
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        // C callback: cannot capture, so recover `self` from the context info pointer and hop
        // back to the main actor to mutate state.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<ActivityMonitor>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in monitor.markActive() }
        }
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            watchedPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,   // latency: coalesce event bursts
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        idleTimer?.invalidate(); idleTimer = nil
    }

    private func markActive() {
        if !isBusy { isBusy = true; onChange?(true) }
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.markIdle() }
        }
    }

    private func markIdle() {
        if isBusy { isBusy = false; onChange?(false) }
    }
}
