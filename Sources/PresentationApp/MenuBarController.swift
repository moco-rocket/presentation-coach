import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onStart: () -> Void
    private let onStop: () -> Void
    private let onQuit: () -> Void

    let statusMenuItem = NSMenuItem(title: "待機中", action: nil, keyEquivalent: "")
    let startMenuItem = NSMenuItem(title: "練習を開始", action: nil, keyEquivalent: "")
    let stopMenuItem = NSMenuItem(title: "練習を停止", action: nil, keyEquivalent: "")

    init(
        statusBar: NSStatusBar = .system,
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        self.onStart = onStart
        self.onStop = onStop
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
        statusItem.button?.appearsDisabled = false
        statusItem.button?.contentTintColor = isRunning ? .systemRed : nil
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

    private func configureButton() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "person.3.sequence.fill",
            accessibilityDescription: "Presentation Coach"
        )
        statusItem.button?.toolTip = "Presentation Coach"
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
