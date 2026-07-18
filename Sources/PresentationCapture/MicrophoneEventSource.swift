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
    private var isRunning = false

    public init(
        sessionID: UUID,
        speechThresholdDB: Double = -42,
        handler: @escaping @Sendable (PresentationEvent) -> Void
    ) {
        self.engine = AVAudioEngine()
        self.sessionID = sessionID
        self.startedAt = .now
        self.handler = handler
        self.analyzer = LockedAudioAnalyzer(speechThresholdDB: speechThresholdDB)
    }

    public func start() throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sessionID = sessionID
        let startedAt = startedAt
        let handler = handler
        let analyzer = analyzer

        input.installTap(onBus: 0, bufferSize: 960, format: format) { buffer, _ in
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
        try engine.start()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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
