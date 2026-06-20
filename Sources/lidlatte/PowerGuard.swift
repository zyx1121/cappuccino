import Foundation
import IOKit.ps

/// Battery / power telemetry plus a power-source-change signal.
///
/// The change signal matters on Apple Silicon: connecting or disconnecting AC can reset
/// `disablesleep`, so the coordinator must re-apply on every transition (Amphetamine ships a
/// whole script for exactly this). We just fire `onPowerChange` and let the coordinator reconcile.
@MainActor
final class PowerGuard {
    var onPowerChange: (() -> Void)?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        let info = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let guardian = Unmanaged<PowerGuard>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in guardian.onPowerChange?() }
        }
        guard let src = IOPSNotificationCreateRunLoopSource(callback, info)?.takeRetainedValue() else { return }
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
    }

    func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .defaultMode)
            runLoopSource = nil
        }
    }

    var isLowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// Parse `pmset -g batt` (no root). Returns (onBattery, discharging, percent).
    func batteryStatus() -> (onBattery: Bool, discharging: Bool, percent: Int) {
        let out = runCapture("/usr/bin/pmset", ["-g", "batt"])
        let onBattery = out.contains("Battery Power")
        let discharging = out.range(of: "discharging", options: .caseInsensitive) != nil
        var percent = 100
        for tok in out.split(whereSeparator: { " \t\n;".contains($0) }) where tok.hasSuffix("%") {
            if let v = Int(tok.dropLast()) { percent = v; break }
        }
        return (onBattery, discharging, percent)
    }

    private func runCapture(_ launchPath: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
