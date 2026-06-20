import AppKit

/// The brain: turns three inputs — Claude Code activity, the user's menu choices, and power
/// state — into the one output that matters (`disablesleep` on/off), and keeps the system
/// reconciled to that decision.
///
/// Desired keep-awake = (manual override OR (auto && agent busy)), then vetoed by the safety
/// nets: a hard battery floor (wins even over a manual override — never drain to empty) and
/// Low Power Mode (unless the user deliberately forced it on this session).
@MainActor
final class Coordinator {
    private let sleep = SleepController()
    private let activity = ActivityMonitor()
    private let power = PowerGuard()
    private var pollTimer: Timer?

    private var batteryStopActive = false
    /// Once a passive trigger discovers the sudoers grant is missing, stop hammering sudo and
    /// re-notifying on every reconcile — wait for a deliberate user toggle to retry (which is
    /// also the only context allowed to pop the auth sheet).
    private var grantKnownMissing = false

    /// Auto mode: keep awake (incl. lid closed) while Claude Code is working. Persisted.
    var autoEnabled: Bool {
        didSet { UserDefaults.standard.set(autoEnabled, forKey: "autoEnabled"); reconcile(interactive: true) }
    }
    /// Manual override: stay awake regardless of detection. NOT persisted — never silently
    /// re-arm an unattended keep-awake across launches (mirrors disablesleep's reboot reset).
    var manualOverride = false { didSet { reconcile(interactive: true) } }
    /// Hard battery floor (%). Below this, on battery, force normal sleep — even over a manual
    /// override. Persisted.
    var batteryFloor: Int {
        didSet { UserDefaults.standard.set(batteryFloor, forKey: "batteryFloor"); reconcile(interactive: true) }
    }

    var onStateChange: (() -> Void)?

    init() {
        let d = UserDefaults.standard
        self.autoEnabled = (d.object(forKey: "autoEnabled") as? Bool) ?? true
        self.batteryFloor = (d.object(forKey: "batteryFloor") as? Int) ?? 15
    }

    func start() {
        activity.onChange = { [weak self] _ in self?.reconcile() }
        power.onPowerChange = { [weak self] in self?.reconcile() }   // AS: re-apply on AC change
        activity.start()
        power.start()
        // Periodic reconcile catches a slowly-draining battery crossing the floor.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        reconcile()   // reflect TRUE system state on launch; never assume
    }

    /// Stop keeping the Mac awake and restore normal sleep — called on quit so an unattended
    /// machine is never left unable to sleep with no app managing the safety nets.
    func shutdown() {
        activity.stop(); power.stop(); pollTimer?.invalidate()
        if sleep.isSleepDisabled() { sleep.setSleepDisabled(false) }
    }

    var isBusy: Bool { activity.isBusy }
    var isKeepingAwake: Bool { sleep.isSleepDisabled() }

    enum Mode { case sleeping, autoActive, manual }
    var mode: Mode {
        if !sleep.isSleepDisabled() { return .sleeping }
        return manualOverride ? .manual : .autoActive
    }

    /// `interactive` is true only when the user just changed a setting — the one time we're
    /// allowed to pop the native auth sheet to install the grant, and the one time we retry a
    /// previously-missing grant. Passive triggers (file events, power changes, poll) never
    /// prompt and never hammer sudo once the grant is known missing.
    func reconcile(interactive: Bool = false) {
        if interactive { grantKnownMissing = false }

        let (onBatt, discharging, pct) = power.batteryStatus()
        let wantBase = manualOverride || (autoEnabled && activity.isBusy)
        let belowFloor = onBatt && discharging && pct <= batteryFloor
        let lpmBlocks = power.isLowPowerMode && !manualOverride
        let want = wantBase && !belowFloor && !lpmBlocks
        let have = sleep.isSleepDisabled()

        // Battery floor just forced us off (we wanted awake but the floor vetoed) — say so once.
        if wantBase, belowFloor, have, !batteryStopActive {
            notify("電量低於 \(batteryFloor)%,已恢復正常睡眠。")
        }
        batteryStopActive = wantBase && belowFloor

        if want != have && !(want && grantKnownMissing && !interactive) {
            var result = sleep.setSleepDisabled(want)
            if want, result == .grantMissing, interactive, sleep.installGrant() {
                result = sleep.setSleepDisabled(true)
            }
            switch result {
            case .ok:
                grantKnownMissing = false
            case .grantMissing:
                if !grantKnownMissing {   // first discovery → notify exactly once
                    notify(interactive
                           ? "授權未完成,無法闔蓋不睡。"
                           : "lidlatte 偵測到 Claude Code 在工作,需要授權才能闔蓋不睡:點選單列圖示開「持續闔蓋不睡」一次即可授權。")
                }
                grantKnownMissing = true
            case .failed(let msg):
                NSLog("lidlatte: disablesleep toggle failed: %@", msg)
            }
        }
        onStateChange?()
    }

    private func notify(_ message: String) {
        let script = "display notification \"\(message)\" with title \"lidlatte\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }
}
