import Foundation
import PresentationCapture
import PresentationContracts
import PresentationFeedback

actor LivePracticePipeline {
    typealias EventSink = @Sendable (PresentationEvent) async -> Void

    let sessionID: UUID
    private let hub: SessionEventHub
    private let ruleEngine: RuleEngine
    private let director: FeedbackDirector
    private let sink: EventSink
    private var eventTask: Task<Void, Never>?
    private var lastAudioRuleEvaluationMs: Int64?
    private var isStopping = false
    private var pendingInputCount = 0
    private var drainContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        sessionID: UUID = UUID(),
        recordingURL: URL? = nil,
        ruleEngine: RuleEngine = RuleEngine(),
        director: FeedbackDirector = FeedbackDirector(),
        sink: @escaping EventSink
    ) {
        self.sessionID = sessionID
        hub = SessionEventHub(sessionID: sessionID, recordingURL: recordingURL)
        self.ruleEngine = ruleEngine
        self.director = director
        self.sink = sink
    }

    func start(descriptor: SessionDescriptor) async throws {
        guard eventTask == nil else { throw LivePracticePipelineError.alreadyStarted }
        let stream = await hub.events(bufferingNewest: 512)
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.process(event)
            }
        }
        do {
            try await hub.start(descriptor: descriptor)
        } catch {
            eventTask?.cancel()
            eventTask = nil
            throw error
        }
    }

    func ingest(_ event: PresentationEvent) async throws {
        guard !isStopping else { throw LivePracticePipelineError.stopping }
        guard event.sessionID == sessionID else {
            throw LivePracticePipelineError.sessionMismatch
        }
        pendingInputCount += 1
        do {
            _ = try await hub.emit(
                kind: event.kind,
                payload: event.payload,
                timestampMs: event.timestampMs
            )
        } catch {
            finishPendingInput()
            throw error
        }
    }

    func stop() async throws {
        guard let eventTask else { throw LivePracticePipelineError.notStarted }
        isStopping = true
        await waitForInputsToDrain()
        _ = try await hub.stop()
        await eventTask.value
        self.eventTask = nil
        isStopping = false
        lastAudioRuleEvaluationMs = nil
        await director.reset()
    }

    private func process(_ event: PresentationEvent) async {
        defer {
            if Self.isInputKind(event.kind) {
                finishPendingInput()
            }
        }
        await sink(event)
        guard shouldEvaluateRules(for: event) else { return }

        let candidates = ruleEngine.candidates(for: event)
        guard !candidates.isEmpty else { return }

        for candidate in candidates {
            _ = try? await hub.emit(
                kind: .ruleCommentCandidate,
                payload: .commentCandidate(candidate),
                timestampMs: event.timestampMs
            )
        }

        if let reaction = await director.select(from: candidates, at: event.timestampMs) {
            _ = try? await hub.emit(
                kind: .judgeReaction,
                payload: .judgeReaction(reaction),
                timestampMs: event.timestampMs
            )
        }
    }

    private func shouldEvaluateRules(for event: PresentationEvent) -> Bool {
        guard event.kind == .audioMetric else { return true }
        if let lastAudioRuleEvaluationMs,
           event.timestampMs - lastAudioRuleEvaluationMs < 200 {
            return false
        }
        lastAudioRuleEvaluationMs = event.timestampMs
        return true
    }

    private func waitForInputsToDrain() async {
        guard pendingInputCount > 0 else { return }
        await withCheckedContinuation { continuation in
            drainContinuations.append(continuation)
        }
    }

    private func finishPendingInput() {
        pendingInputCount = max(0, pendingInputCount - 1)
        guard pendingInputCount == 0 else { return }
        let continuations = drainContinuations
        drainContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private static func isInputKind(_ kind: PresentationEventKind) -> Bool {
        switch kind {
        case .audioMetric, .speechPartial, .speechFinal, .slideChanged, .timerUpdated:
            true
        default:
            false
        }
    }
}

enum LivePracticePipelineError: Error, Equatable {
    case alreadyStarted
    case notStarted
    case sessionMismatch
    case stopping
}
