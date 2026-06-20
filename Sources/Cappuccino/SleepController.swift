import AppKit

/// Result of a privileged `pmset disablesleep` toggle, based on sudo's REAL exit status.
/// `.ok` = the command ran; `.grantMissing` = the passwordless sudoers grant is absent
/// (the one case that warrants the one-time setup); `.failed` = anything else.
enum SleepToggleResult: Equatable { case ok, grantMissing, failed(String) }

/// Owns the privileged levers this app pulls: macOS' undocumented-but-real `pmset disablesleep`
/// (the ONLY thing that keeps a Mac awake with the lid closed — an IOPMAssertion / `caffeinate`
/// cannot, since lid close is forced sleep, not idle sleep), plus `pmset displaysleepnow` to
/// park the built-in panel. Reads need no root; writes go through a tightly-scoped passwordless
/// sudoers grant so a GUI app can flip them without a password prompt every time.
@MainActor
final class SleepController {
    /// Read current state (no root). `pmset -g` prints `SleepDisabled  1` when enabled.
    func isSleepDisabled() -> Bool {
        let out = runCapture("/usr/bin/pmset", ["-g"])
        for line in out.split(whereSeparator: { $0 == "\n" })
        where line.range(of: "SleepDisabled", options: .caseInsensitive) != nil {
            let toks = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let last = toks.last { return last == "1" }
        }
        return false   // line absent → off
    }

    /// Flip lid-close sleep prevention. Uses `sudo -n` (never prompt: a GUI app has no TTY)
    /// against the exact argv the NOPASSWD grant permits. Decides purely on sudo's exit status,
    /// never on a follow-up SleepDisabled read — a safety net flipping sleep back on must NOT
    /// look like "permission missing" and trigger a spurious auth prompt.
    @discardableResult
    func setSleepDisabled(_ on: Bool) -> SleepToggleResult {
        let (exit, _, err) = runPrivileged(["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"])
        if exit == 0 { return .ok }
        let e = err.lowercased()
        if e.contains("a password is required") || e.contains("not allowed") || e.contains("may not run") {
            return .grantMissing
        }
        return .failed(err.isEmpty ? "exit \(exit)" : err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Immediately sleep the built-in display (does NOT sleep the system). Routed through the
    /// same passwordless grant so it works regardless of whether it needs root. Best-effort —
    /// if the installed grant predates this command the display just stays on; no error surfaced.
    func displaySleepNow() {
        _ = runPrivileged(["-n", "/usr/bin/pmset", "displaysleepnow"])
    }

    /// Install the one-time scoped grant via a SINGLE native auth sheet (Touch ID / password)
    /// — no Terminal. Runs the bundled, audited grant.sh as root through osascript; grant.sh is
    /// root-aware and writes the sudoers drop-in directly. Returns true once the grant is in
    /// place; afterwards the app never asks again.
    func installGrant() -> Bool {
        let intro = NSAlert()
        intro.alertStyle = .informational
        intro.messageText = "啟用闔蓋不睡"
        intro.informativeText = "Cappuccino 需要切換受保護的 macOS 設定(pmset disablesleep / displaysleepnow),請授權一次。macOS 會要求驗證(Touch ID 或密碼)。之後切換即時生效,不再詢問。"
        intro.addButton(withTitle: "啟用")
        intro.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard intro.runModal() == .alertFirstButtonReturn else { return false }

        guard let res = Bundle.main.resourcePath else { return false }
        let grant = res + "/grant.sh"
        // Under the native auth sheet grant.sh runs as root with SUDO_USER unset, so pass the
        // real user explicitly or the grant would be written for "root" (useless).
        let shellCmd = "CAPPUCCINO_USER='\(NSUserName())' /bin/bash '\(grant)' --yes"
        let escaped = shellCmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(escaped)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", osa]
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return false }
        return proc.terminationStatus == 0
    }

    // MARK: - Process runners

    /// Run a privileged command via sudo, capturing exit + stderr. stdin = /dev/null so a GUI
    /// process with no controlling TTY can never block on a prompt — this is what lets the app
    /// KNOW whether its own toggle worked.
    private func runPrivileged(_ args: [String]) -> (exit: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = args
        p.environment = sanitizedEnv()
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "", "launch failed: \(error.localizedDescription)") }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }

    @discardableResult
    private func runCapture(_ launchPath: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.environment = sanitizedEnv()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func sanitizedEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        return env
    }
}
