import AVFoundation
import Foundation
import PresentationContracts

@MainActor
public final class MicrophoneEventSource {
    private let engine: AVAudioEngine
    private let sessionID: UUID
    private let startedAt: ContinuousClock.Instant
    private let handler: @Sendable (PresentationEvent) -> Void
    private let analyzer: LockedAudioAnalyzer
    private let transcriber: (any TranscriptionProviding)?
    private var isRunning = false

    public init(
        sessionID: UUID,
        speechThresholdDB: Double = -42,
        transcriber: (any TranscriptionProviding)? = nil,
        handler: @escaping @Sendable (PresentationEvent) -> Void
    ) {
        self.engine = AVAudioEngine()
        self.sessionID = sessionID
        self.startedAt = .now
        self.handler = handler
        self.analyzer = LockedAudioAnalyzer(speechThresholdDB: speechThresholdDB)
        self.transcriber = transcriber
    }

    public func start() throws {
        guard !isRunning else { return }
        try transcriber?.start()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sessionID = sessionID
        let startedAt = startedAt
        let handler = handler
        let analyzer = analyzer
        let transcriber = transcriber

        input.installTap(onBus: 0, bufferSize: 960, format: format) { buffer, _ in
            transcriber?.append(buffer)
            guard let channel = buffer.floatChannelData?.pointee else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let metric = analyzer.analyze(samples: samples, sampleRate: format.sampleRate)
            let duration = startedAt.duration(to: .now)
            let timestampMs = Int64(duration.components.seconds) * 1_000
                + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
            handler(
                PresentationEvent(
                    sessionID: sessionID,
                    timestampMs: timestampMs,
                    kind: .audioMetric,
                    payload: .audioMetric(metric)
                )
            )
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            transcriber?.stop()
            throw error
        }
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        transcriber?.stop()
        isRunning = false
    }
}

private final class LockedAudioAnalyzer: @unchecked Sendable {
    private let lock = NSLock()
    private var analyzer: AudioMetricAnalyzer

    init(speechThresholdDB: Double) {
        self.analyzer = AudioMetricAnalyzer(speechThresholdDB: speechThresholdDB)
    }

    func analyze(samples: [Float], sampleRate: Double) -> AudioMetric {
        lock.lock()
        defer { lock.unlock() }
        return analyzer.analyze(samples: samples, sampleRate: sampleRate)
    }
}
