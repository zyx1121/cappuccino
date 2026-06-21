import Foundation

/// Watches Claude Code's on-disk activity (session transcripts under ~/.claude/projects) via
/// FSEvents and exposes a debounced "busy" signal: `isBusy` flips true on any file event and
/// back to false after `idleTimeout` of silence.
///
/// "Busy" is a PROXY for "an agent is working": Claude Code appends to its session .jsonl on
/// every turn / tool call, so disk churn ≈ active work. Two refinements close the obvious gaps:
///   • idleTimeout is generous (180s) so a single long inference with no writes isn't mistaken
///     for finished work.
///   • `tick()` (polled by the coordinator) ends keep-awake promptly when NO `claude` process
///     is left alive — finishing all sessions sleeps the Mac without waiting out the timeout.
/// Residual blind spot: one inference longer than idleTimeout while a claude process is still
/// alive can still read as idle; killing that fully needs a streaming busy signal Claude Code
/// doesn't expose.
@MainActor
final class ActivityMonitor {
    private(set) var isBusy = false
    var onChange: ((Bool) -> Void)?

    private let idleTimeout: TimeInterval
    private let watchedPaths: [String]
    private var stream: FSEventStreamRef?
    private var idleTimer: Timer?
    private let queue = DispatchQueue(label: "tw.zyx.cappuccino.fsevents")

    init(idleTimeout: TimeInterval = 180) {
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

    /// Poll-driven (called by the coordinator): if we think we're busy but no Claude Code
    /// process is alive, the work is over — go idle now instead of waiting out idleTimeout.
    func tick() {
        if isBusy && !hasClaudeProcess() { markIdle() }
    }

    /// True if any Claude Code CLI process (`claude`) is running. A probe failure is treated as
    /// "present" (fail-safe: don't sleep out from under a possibly-working agent).
    private func hasClaudeProcess() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", "claude"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run() } catch { return true }
        p.waitUntilExit()
        return p.terminationStatus == 0
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
