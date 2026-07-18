import AVFoundation
import CoreGraphics
import Foundation
import PresentationCapture
import PresentationContracts
import PresentationFeedback
import PresentationOverlay
import Speech

@MainActor
final class LivePracticeCoordinator {
    private let viewModel: OverlayViewModel
    private let recordingDirectory: URL
    private var pipeline: LivePracticePipeline?
    private var microphone: MicrophoneEventSource?
    private var screenCapture: ScreenCaptureSource?

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
        guard CGPreflightScreenCaptureAccess() else {
            throw LivePracticeCoordinatorError.screenRecordingPermissionRequired
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw LivePracticeCoordinatorError.speechRecognitionPermissionRequired
        }

        let sessionID = UUID()
        let recordingURL = recordingDirectory.appendingPathComponent("\(sessionID.uuidString).jsonl")
        let viewModel = self.viewModel
        let commentGenerator = try? OpenAICommentGenerator.fromEnvironment()
        let pipeline = LivePracticePipeline(
            sessionID: sessionID,
            recordingURL: recordingURL,
            commentGenerator: commentGenerator
        ) { event in
            await MainActor.run { viewModel.consume(event) }
        }

        try await pipeline.start(descriptor: descriptor)
        let transcriber = AppleSpeechTranscriber(sessionID: sessionID) { event in
            Task { try? await pipeline.ingest(event) }
        }
        let microphone = MicrophoneEventSource(sessionID: sessionID, transcriber: transcriber) { event in
            Task { try? await pipeline.ingest(event) }
        }
        let screenCapture = ScreenCaptureSource()
        let slideAnalyzer = SlideFrameAnalyzer()

        do {
            try microphone.start()
            try await screenCapture.start(displayID: CGMainDisplayID()) { frame in
                guard let slide = try? await slideAnalyzer.analyze(frame) else { return }
                try? await pipeline.ingest(PresentationEvent(
                    sessionID: sessionID,
                    timestampMs: frame.timestampMs,
                    kind: .slideChanged,
                    payload: .slideChange(slide)
                ))
            }
        } catch {
            microphone.stop()
            await screenCapture.stop()
            try? await pipeline.stop()
            throw error
        }

        self.pipeline = pipeline
        self.microphone = microphone
        self.screenCapture = screenCapture
        self.recordingURL = recordingURL
    }

    func stop() async -> SessionReport? {
        microphone?.stop()
        microphone = nil
        await screenCapture?.stop()
        screenCapture = nil
        guard let pipeline else { return nil }
        try? await pipeline.stop()
        self.pipeline = nil
        guard let recordingURL,
              let events = try? JSONLEventReader.read(from: recordingURL) else { return nil }
        return try? SessionReportBuilder.build(from: events)
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
    case screenRecordingPermissionRequired
    case speechRecognitionPermissionRequired

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: "練習はすでに開始しています。"
        case .microphonePermissionRequired: "練習を開始するにはマイクの許可が必要です。"
        case .screenRecordingPermissionRequired: "練習を開始するには画面収録の許可が必要です。"
        case .speechRecognitionPermissionRequired: "練習を開始するには音声認識の許可が必要です。"
        }
    }
}
