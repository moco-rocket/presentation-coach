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
        application.setActivationPolicy(configuration.mode == .uiDemo ? .accessory : .regular)
        installMainMenu()
        application.delegate = self
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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

    private func shutDown() {
        guard !hasShutDown else { return }
        hasShutDown = true
        automaticTerminationTimer?.invalidate()
        automaticTerminationTimer = nil
        timeline?.stop()
        viewModel.clearReaction()
        overlayController.hide()
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
