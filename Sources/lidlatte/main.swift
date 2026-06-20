import AppKit

// SwiftPM treats a file named main.swift as top-level code, so the entry point lives here
// directly (no @main). The global `delegate` binding keeps it alive for the app's lifetime.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
