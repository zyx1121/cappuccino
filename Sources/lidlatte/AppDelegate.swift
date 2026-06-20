import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let coord = Coordinator()
    private let floorOptions = [5, 10, 15, 20, 25, 30]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menubar-only (LSUIElement)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        coord.onStateChange = { [weak self] in self?.updateUI() }
        coord.start()
        buildMenu()
        updateUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coord.shutdown()   // restore normal sleep; never leave an unattended Mac unable to sleep
    }

    // MARK: - Menu construction

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false; status.tag = 100
        menu.addItem(status)
        menu.addItem(.separator())

        let auto = NSMenuItem(title: "Claude Code 工作時不睡", action: #selector(toggleAuto), keyEquivalent: "")
        auto.target = self; auto.tag = 101
        menu.addItem(auto)

        let manual = NSMenuItem(title: "持續闔蓋不睡", action: #selector(toggleManual), keyEquivalent: "")
        manual.target = self; manual.tag = 102
        menu.addItem(manual)

        let floor = NSMenuItem(title: "低電量自動關", action: nil, keyEquivalent: "")
        floor.tag = 103
        let floorMenu = NSMenu()
        for pct in floorOptions {
            let item = NSMenuItem(title: "\(pct) %", action: #selector(setFloor(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = pct
            floorMenu.addItem(item)
        }
        floor.submenu = floorMenu
        menu.addItem(floor)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "結束 lidlatte", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // Refresh against TRUE system state right before the menu shows.
    func menuWillOpen(_ menu: NSMenu) { coord.reconcile() }

    // MARK: - Actions

    @objc private func toggleAuto() { coord.autoEnabled.toggle() }
    @objc private func toggleManual() { coord.manualOverride.toggle() }
    @objc private func setFloor(_ sender: NSMenuItem) {
        if let pct = sender.representedObject as? Int { coord.batteryFloor = pct }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - UI sync

    private func updateUI() {
        guard let menu = statusItem.menu else { return }

        if let button = statusItem.button {
            let name = coord.isKeepingAwake ? "bolt.fill" : "moon.zzz"
            let img = NSImage(systemSymbolName: name, accessibilityDescription: "lidlatte")
            img?.isTemplate = true
            button.image = img
        }

        if let s = menu.item(withTag: 100) {
            switch coord.mode {
            case .sleeping:   s.title = coord.isBusy ? "偵測到工作,啟用中…" : "正常睡眠"
            case .autoActive: s.title = "闔蓋不睡中(自動)"
            case .manual:     s.title = "闔蓋不睡中(手動)"
            }
        }
        menu.item(withTag: 101)?.state = coord.autoEnabled ? .on : .off
        menu.item(withTag: 102)?.state = coord.manualOverride ? .on : .off
        if let floor = menu.item(withTag: 103) {
            floor.title = "低電量自動關(\(coord.batteryFloor) %)"
            floor.submenu?.items.forEach { item in
                if let pct = item.representedObject as? Int {
                    item.state = (coord.batteryFloor == pct) ? .on : .off
                }
            }
        }
    }
}
