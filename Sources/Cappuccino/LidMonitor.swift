import Foundation
import IOKit

/// Detects MacBook lid open/close via IOPMrootDomain's `AppleClamshellState` and fires on
/// change. Used to protect the built-in display: while keeping the Mac awake with the lid
/// closed, `disablesleep` can leave the internal panel powered → burn-in + wasted battery, so
/// the coordinator forces the display to sleep when the lid folds shut.
@MainActor
final class LidMonitor {
    var onLidChange: (() -> Void)?

    private var notifyPort: IONotificationPortRef?
    private var interest: io_object_t = 0
    private var rootDomain: io_service_t = 0

    /// True when the lid is folded shut. `AppleClamshellState` reads Yes when closed.
    func isLidClosed() -> Bool {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != 0 else { return false }
        defer { IOObjectRelease(entry) }
        guard let cf = IORegistryEntryCreateCFProperty(entry, "AppleClamshellState" as CFString,
                                                        kCFAllocatorDefault, 0)?.takeRetainedValue()
        else { return false }
        // AppleClamshellState is a CFBoolean; bridge it properly (a blind `as? Bool` can fail).
        if CFGetTypeID(cf) == CFBooleanGetTypeID() { return CFBooleanGetValue((cf as! CFBoolean)) }
        return (cf as? NSNumber)?.boolValue ?? false
    }

    func start() {
        guard notifyPort == nil else { return }
        rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)   // deliver callbacks on main
        let info = Unmanaged.passUnretained(self).toOpaque()
        // C callback: recover self from refcon, hop to main actor. We don't filter the message
        // type — any IOPMrootDomain interest event just re-evaluates lid state (idempotent).
        let callback: IOServiceInterestCallback = { refcon, _, _, _ in
            guard let refcon else { return }
            let monitor = Unmanaged<LidMonitor>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in monitor.onLidChange?() }
        }
        IOServiceAddInterestNotification(port, rootDomain, kIOGeneralInterest, callback, info, &interest)
    }

    func stop() {
        if interest != 0 { IOObjectRelease(interest); interest = 0 }
        if let port = notifyPort { IONotificationPortDestroy(port); notifyPort = nil }
        if rootDomain != 0 { IOObjectRelease(rootDomain); rootDomain = 0 }
    }
}
