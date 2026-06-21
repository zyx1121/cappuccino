import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let coord = Coordinator()
    private let floorOptions = [5, 10, 15, 20, 25, 30]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menubar-only (LSUIElement)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setMenubarIcon()
        coord.onStateChange = { [weak self] in self?.updateUI() }
        coord.start()
        buildMenu()
        updateUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coord.shutdown()   // restore normal sleep; never leave an unattended Mac unable to sleep
    }

    // MARK: - Menubar icon

    // 選單列圖示 = 全家共用的 zyx 品牌標(Resources/MenubarIcon.pdf,template),設一次即可。
    // 狀態(闔蓋不睡 / 正常睡眠)靠選單裡的狀態文字表達,不靠這顆圖示切換。找不到才退回 SF Symbol。
    private func setMenubarIcon() {
        guard let button = statusItem.button else { return }
        if let p = Bundle.main.path(forResource: "MenubarIcon", ofType: "pdf"),
           let mark = NSImage(contentsOfFile: p) {
            let h: CGFloat = 18
            mark.size = NSSize(width: h * mark.size.width / max(mark.size.height, 1), height: h)
            mark.isTemplate = true
            button.image = mark
        } else {
            button.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Cappuccino")
            button.image?.isTemplate = true
        }
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
        let quit = NSMenuItem(title: "結束 Cappuccino", action: #selector(quit), keyEquivalent: "q")
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

        // 選單列圖示固定為 zyx mark(在 launch 設一次),狀態變化只更新下面的狀態文字。
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
