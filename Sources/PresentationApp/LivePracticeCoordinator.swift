import AVFoundation
import Foundation
import PresentationCapture
import PresentationContracts
import PresentationOverlay

@MainActor
final class LivePracticeCoordinator {
    private let viewModel: OverlayViewModel
    private let recordingDirectory: URL
    private var pipeline: LivePracticePipeline?
    private var microphone: MicrophoneEventSource?

    private(set) var recordingURL: URL?

    init(viewModel: OverlayViewModel, recordingDirectory: URL? = nil) {
        self.viewModel = viewModel
        self.recordingDirectory = recordingDirectory ?? Self.defaultRecordingDirectory()
    }

    func start(descriptor: SessionDescriptor) async throws {
        guard pipeline == nil else { throw LivePracticeCoordinatorError.alreadyRunning }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw LivePracticeCoordinatorError.microphonePermissionRequired
        }

        let sessionID = UUID()
        let recordingURL = recordingDirectory.appendingPathComponent("\(sessionID.uuidString).jsonl")
        let viewModel = self.viewModel
        let pipeline = LivePracticePipeline(
            sessionID: sessionID,
            recordingURL: recordingURL
        ) { event in
            await MainActor.run { viewModel.consume(event) }
        }

        try await pipeline.start(descriptor: descriptor)
        let microphone = MicrophoneEventSource(sessionID: sessionID) { event in
            Task { try? await pipeline.ingest(event) }
        }

        do {
            try microphone.start()
        } catch {
            try? await pipeline.stop()
            throw error
        }

        self.pipeline = pipeline
        self.microphone = microphone
        self.recordingURL = recordingURL
    }

    func stop() async {
        microphone?.stop()
        microphone = nil
        guard let pipeline else { return }
        try? await pipeline.stop()
        self.pipeline = nil
    }

    private static func defaultRecordingDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("PresentationCoach", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
    }
}

enum LivePracticeCoordinatorError: Error, LocalizedError, Equatable {
    case alreadyRunning
    case microphonePermissionRequired

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: "練習はすでに開始しています。"
        case .microphonePermissionRequired: "練習を開始するにはマイクの許可が必要です。"
        }
    }
}
