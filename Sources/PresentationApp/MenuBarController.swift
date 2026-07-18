import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onStart: () -> Void
    private let onStop: () -> Void
    private let onShowPermissions: () -> Void
    private let onShowHistory: () -> Void
    private let onQuit: () -> Void

    let statusMenuItem = NSMenuItem(title: "待機中", action: nil, keyEquivalent: "")
    let startMenuItem = NSMenuItem(title: "練習を開始", action: nil, keyEquivalent: "")
    let stopMenuItem = NSMenuItem(title: "練習を停止", action: nil, keyEquivalent: "")

    init(
        statusBar: NSStatusBar = .system,
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onShowPermissions: @escaping () -> Void = {},
        onShowHistory: @escaping () -> Void = {},
        onQuit: @escaping () -> Void
    ) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        self.onStart = onStart
        self.onStop = onStop
        self.onShowPermissions = onShowPermissions
        self.onShowHistory = onShowHistory
        self.onQuit = onQuit
        super.init()

        configureButton()
        configureMenu()
        setSessionRunning(false)
    }

    func setSessionRunning(_ isRunning: Bool) {
        statusMenuItem.title = isRunning ? "練習中" : "待機中"
        startMenuItem.isEnabled = !isRunning
        stopMenuItem.isEnabled = isRunning
        let symbolName = isRunning ? "record.circle.fill" : "person.3.sequence.fill"
        let description = isRunning ? "Presentation Coach — 練習中" : "Presentation Coach — 待機中"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = nil
        statusItem.button?.appearsDisabled = false
        statusItem.button?.toolTip = description
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc func startPractice() {
        onStart()
    }

    @objc func stopPractice() {
        onStop()
    }

    @objc func quitApplication() {
        onQuit()
    }

    @objc func showPermissions() {
        onShowPermissions()
    }

    @objc func showHistory() {
        onShowHistory()
    }

    private func configureButton() {
        statusItem.button?.toolTip = "Presentation Coach — 待機中"
    }

    private func configureMenu() {
        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        startMenuItem.target = self
        startMenuItem.action = #selector(startPractice)
        menu.addItem(startMenuItem)

        stopMenuItem.target = self
        stopMenuItem.action = #selector(stopPractice)
        menu.addItem(stopMenuItem)

        menu.addItem(.separator())
        let historyMenuItem = NSMenuItem(
            title: "練習履歴…",
            action: #selector(showHistory),
            keyEquivalent: ""
        )
        historyMenuItem.target = self
        menu.addItem(historyMenuItem)

        let permissionMenuItem = NSMenuItem(
            title: "権限を確認…",
            action: #selector(showPermissions),
            keyEquivalent: ""
        )
        permissionMenuItem.target = self
        menu.addItem(permissionMenuItem)

        menu.addItem(.separator())
        let quitMenuItem = NSMenuItem(
            title: "Presentation Coachを終了",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        statusItem.menu = menu
    }
}
