import AppKit
import Foundation
import PresentationContracts
import PresentationOverlay

@MainActor
final class PresentationMacApplication: NSObject, NSApplicationDelegate {
    private let configuration: ApplicationConfiguration
    private let application: NSApplication
    private let viewModel: OverlayViewModel
    private let overlayController: OverlayPanelController
    private let timeline: FixtureTimeline?

    private var automaticTerminationTimer: Timer?
    private var menuBarController: MenuBarController?
    private var permissionGuideController: PermissionGuideWindowController?
    private var liveSessionID: UUID?
    private var liveSessionStartedAt: Date?
    private var hasShutDown = false

    init(configuration: ApplicationConfiguration) throws {
        self.configuration = configuration
        application = .shared
        viewModel = OverlayViewModel()
        overlayController = OverlayPanelController(viewModel: viewModel)

        if configuration.mode == .uiDemo {
            guard let fixtureURL = configuration.fixtureURL else {
                throw PresentationMacApplicationError.missingFixtureURL
            }
            guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
                throw PresentationMacApplicationError.fixtureNotFound(fixtureURL.path)
            }
            timeline = try FixtureTimeline(contentsOf: fixtureURL)
        } else {
            timeline = nil
        }
        super.init()
    }

    func run() {
        application.setActivationPolicy(.accessory)
        installMainMenu()
        application.delegate = self
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if configuration.mode == .idle {
            installMenuBarController()
            return
        }

        overlayController.show()
        guard let timeline else { return }
        do {
            try timeline.play(speed: configuration.playbackSpeed) { [weak viewModel] event in
                viewModel?.consume(event)
            }
            scheduleAutomaticTermination(for: timeline.events)
        } catch {
            fputs("Unable to start UI demo: \(error.localizedDescription)\n", stderr)
            application.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutDown()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Presentation Coachを終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        application.mainMenu = mainMenu
    }

    private func scheduleAutomaticTermination(for events: [PresentationEvent]) {
        let firstTimestamp = events.first?.timestampMs ?? 0
        let lastTimestamp = events.last?.timestampMs ?? firstTimestamp
        let playbackDuration = Int64(
            (Double(max(0, lastTimestamp - firstTimestamp)) / configuration.playbackSpeed).rounded(.up)
        )
        let finalReactionDuration: Int64
        if let lastEvent = events.last,
           case .judgeReaction(let reaction) = lastEvent.payload {
            finalReactionDuration = Int64(reaction.durationMs)
        } else {
            finalReactionDuration = 500
        }
        let delay = max(250, playbackDuration + finalReactionDuration + 250)

        automaticTerminationTimer = Timer.scheduledTimer(
            withTimeInterval: Double(delay) / 1_000,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.application.terminate(nil)
            }
        }
    }

    private func installMenuBarController() {
        let permissionGuideController = PermissionGuideWindowController()
        self.permissionGuideController = permissionGuideController
        menuBarController = MenuBarController(
            onStart: { [weak self] in self?.startPractice() },
            onStop: { [weak self] in self?.stopPractice() },
            onShowPermissions: { [weak permissionGuideController] in permissionGuideController?.show() },
            onQuit: { [weak application] in application?.terminate(nil) }
        )
    }

    private func startPractice() {
        guard liveSessionID == nil else { return }
        let sessionID = UUID()
        liveSessionID = sessionID
        liveSessionStartedAt = Date()
        viewModel.consume(PresentationEvent(
            sessionID: sessionID,
            timestampMs: 0,
            kind: .sessionStarted,
            payload: .session(SessionDescriptor(
                title: "発表練習",
                goal: "",
                audience: "",
                plannedDurationSeconds: 0
            ))
        ))
        overlayController.show()
        menuBarController?.setSessionRunning(true)
    }

    private func stopPractice() {
        guard let sessionID = liveSessionID else { return }
        let elapsedMilliseconds = Int64(
            max(0, Date().timeIntervalSince(liveSessionStartedAt ?? Date()) * 1_000)
        )
        viewModel.consume(PresentationEvent(
            sessionID: sessionID,
            timestampMs: elapsedMilliseconds,
            kind: .sessionStopped,
            payload: .none
        ))
        liveSessionID = nil
        liveSessionStartedAt = nil
        overlayController.hide()
        menuBarController?.setSessionRunning(false)
    }

    private func shutDown() {
        guard !hasShutDown else { return }
        hasShutDown = true
        stopPractice()
        automaticTerminationTimer?.invalidate()
        automaticTerminationTimer = nil
        timeline?.stop()
        viewModel.clearReaction()
        overlayController.hide()
        menuBarController?.remove()
        menuBarController = nil
        permissionGuideController?.close()
        permissionGuideController = nil
    }
}

enum PresentationMacApplicationError: Error, LocalizedError, Equatable {
    case missingFixtureURL
    case fixtureNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingFixtureURL:
            return "UI demo fixture URL is missing."
        case .fixtureNotFound(let path):
            return "UI demo fixture was not found at \(path)"
        }
    }
}
