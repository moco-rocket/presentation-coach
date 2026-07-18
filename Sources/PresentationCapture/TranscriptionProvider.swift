import AVFoundation
import Foundation
import PresentationContracts
import Speech

public protocol TranscriptionProviding: AnyObject, Sendable {
    @MainActor func start() throws
    func append(_ buffer: AVAudioPCMBuffer)
    @MainActor func stop()
}

public enum AppleSpeechTranscriberError: Error, LocalizedError, Equatable {
    case recognizerUnavailable
    case authorizationRequired

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: "このMacでは選択した言語の音声認識を利用できません。"
        case .authorizationRequired: "音声認識の許可が必要です。"
        }
    }
}

/// Streams microphone buffers into Apple's speech recognizer and emits both
/// replaceable partial text and durable final text through the shared contract.
public final class AppleSpeechTranscriber: TranscriptionProviding, @unchecked Sendable {
    private let sessionID: UUID
    private let recognizer: SFSpeechRecognizer?
    private let handler: @Sendable (PresentationEvent) -> Void
    private let lock = NSLock()
    private let startedAt = ContinuousClock.now
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestSegment: SpeechSegment?
    private var latestWasFinal = false

    public init(
        sessionID: UUID,
        locale: Locale = Locale(identifier: "ja-JP"),
        handler: @escaping @Sendable (PresentationEvent) -> Void
    ) {
        self.sessionID = sessionID
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.handler = handler
    }

    @MainActor
    public func start() throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw AppleSpeechTranscriberError.authorizationRequired
        }
        guard let recognizer, recognizer.isAvailable else {
            throw AppleSpeechTranscriberError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        lock.lock()
        self.request = request
        latestSegment = nil
        latestWasFinal = false
        lock.unlock()

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            self.consume(result)
        }
    }

    public func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }

    @MainActor
    public func stop() {
        lock.lock()
        let request = self.request
        self.request = nil
        let latestSegment = self.latestSegment
        let shouldFinalize = latestSegment != nil && !latestWasFinal
        lock.unlock()

        request?.endAudio()
        task?.cancel()
        task = nil

        if shouldFinalize, var latestSegment {
            latestSegment.endedAtMs = max(latestSegment.startedAtMs, elapsedMilliseconds)
            handler(PresentationEvent(
                sessionID: sessionID,
                timestampMs: elapsedMilliseconds,
                kind: .speechFinal,
                payload: .speech(latestSegment)
            ))
        }
    }

    private func consume(_ result: SFSpeechRecognitionResult) {
        let transcription = result.bestTranscription
        let segments = transcription.segments
        let firstTimestamp = segments.first?.timestamp ?? 0
        let lastEnd = segments.last.map { $0.timestamp + $0.duration } ?? firstTimestamp
        let confidence: Double? = segments.isEmpty ? nil : Double(
            segments.reduce(Float(0)) { $0 + $1.confidence } / Float(segments.count)
        )
        let segment = SpeechSegment(
            text: transcription.formattedString,
            startedAtMs: Int64(firstTimestamp * 1_000),
            endedAtMs: result.isFinal ? Int64(lastEnd * 1_000) : nil,
            confidence: confidence
        )

        lock.lock()
        latestSegment = segment
        latestWasFinal = result.isFinal
        lock.unlock()

        handler(PresentationEvent(
            sessionID: sessionID,
            timestampMs: elapsedMilliseconds,
            kind: result.isFinal ? .speechFinal : .speechPartial,
            payload: .speech(segment)
        ))
    }

    private var elapsedMilliseconds: Int64 {
        let duration = startedAt.duration(to: .now)
        return Int64(duration.components.seconds) * 1_000
            + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
