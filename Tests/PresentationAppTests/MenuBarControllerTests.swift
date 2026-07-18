import AppKit
import Testing
@testable import PresentationApp

@MainActor
@Test func menuBarStartsInIdleStateAndInvokesActions() {
    _ = NSApplication.shared
    var started = false
    var stopped = false
    var quit = false
    let controller = MenuBarController(
        onStart: { started = true },
        onStop: { stopped = true },
        onQuit: { quit = true }
    )
    defer { controller.remove() }

    #expect(controller.statusMenuItem.title == "待機中")
    #expect(controller.startMenuItem.isEnabled)
    #expect(controller.stopMenuItem.isEnabled == false)

    controller.startPractice()
    controller.stopPractice()
    controller.quitApplication()

    #expect(started)
    #expect(stopped)
    #expect(quit)
}

@MainActor
@Test func menuBarReflectsRunningState() {
    _ = NSApplication.shared
    let controller = MenuBarController(onStart: {}, onStop: {}, onQuit: {})
    defer { controller.remove() }

    controller.setSessionRunning(true)

    #expect(controller.statusMenuItem.title == "練習中")
    #expect(controller.startMenuItem.isEnabled == false)
    #expect(controller.stopMenuItem.isEnabled)
}
