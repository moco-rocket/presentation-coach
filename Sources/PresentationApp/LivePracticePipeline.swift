import Foundation
import PresentationCapture
import PresentationContracts
import PresentationFeedback

actor LivePracticePipeline {
    typealias EventSink = @Sendable (PresentationEvent) async -> Void

    let sessionID: UUID
    private let hub: SessionEventHub
    private let ruleEngine: RuleEngine
    private var slidePacingTracker: SlidePacingTracker
    private let director: FeedbackDirector
    private let commentGenerator: (any CommentGenerating)?
    private let minimumLLMIntervalMs: Int64
    private let llmTimeoutMilliseconds: Int
    private let sink: EventSink
    private var eventTask: Task<Void, Never>?
    private var llmTask: Task<Void, Never>?
    private var lastAudioRuleEvaluationMs: Int64?
    private var lastLLMRequestMs: Int64?
    private var descriptor: SessionDescriptor?
    private var recentTranscript: [(timestampMs: Int64, text: String)] = []
    private var currentPartialTranscript = ""
    private var currentSlideOCR: String?
    private var remainingSeconds = 0
    private var recentDisplayedComments: [String] = []
    private var isStopping = false
    private var pendingInputCount = 0
    private var drainContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        sessionID: UUID = UUID(),
        recordingURL: URL? = nil,
        ruleEngine: RuleEngine = RuleEngine(),
        slidePacingTracker: SlidePacingTracker = SlidePacingTracker(),
        director: FeedbackDirector = FeedbackDirector(),
        commentGenerator: (any CommentGenerating)? = nil,
        minimumLLMIntervalMs: Int64 = 3_000,
        llmTimeoutMilliseconds: Int = 2_500,
        sink: @escaping EventSink
    ) {
        self.sessionID = sessionID
        hub = SessionEventHub(sessionID: sessionID, recordingURL: recordingURL)
        self.ruleEngine = ruleEngine
        self.slidePacingTracker = slidePacingTracker
        self.director = director
        self.commentGenerator = commentGenerator
        self.minimumLLMIntervalMs = max(0, minimumLLMIntervalMs)
        self.llmTimeoutMilliseconds = max(1, llmTimeoutMilliseconds)
        self.sink = sink
    }

    func start(descriptor: SessionDescriptor) async throws {
        guard eventTask == nil else { throw LivePracticePipelineError.alreadyStarted }
        self.descriptor = descriptor
        remainingSeconds = descriptor.plannedDurationSeconds
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
        llmTask?.cancel()
        await llmTask?.value
        llmTask = nil
        _ = try await hub.stop()
        await eventTask.value
        self.eventTask = nil
        isStopping = false
        lastAudioRuleEvaluationMs = nil
        lastLLMRequestMs = nil
        descriptor = nil
        recentTranscript.removeAll()
        currentPartialTranscript = ""
        currentSlideOCR = nil
        remainingSeconds = 0
        recentDisplayedComments.removeAll()
        slidePacingTracker.reset()
        await director.reset()
    }

    private func process(_ event: PresentationEvent) async {
        defer {
            if Self.isInputKind(event.kind) {
                finishPendingInput()
            }
        }
        await sink(event)
        updateLLMContext(with: event)
        scheduleLLMIfNeeded(for: event)
        guard shouldEvaluateRules(for: event) else { return }

        let candidates = ruleEngine.candidates(for: event) + slidePacingTracker.candidates(for: event)
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

    private func updateLLMContext(with event: PresentationEvent) {
        switch event.payload {
        case let .speech(segment):
            if event.kind == .speechFinal {
                recentTranscript.append((event.timestampMs, segment.text))
                recentTranscript.removeAll { event.timestampMs - $0.timestampMs > 30_000 }
                currentPartialTranscript = ""
            } else if event.kind == .speechPartial {
                currentPartialTranscript = segment.text
            }
        case let .slideChange(slide):
            currentSlideOCR = slide.ocrText
        case let .timer(timer):
            remainingSeconds = timer.remainingSeconds
        case let .judgeReaction(reaction):
            recentDisplayedComments.append(reaction.text)
            recentDisplayedComments = Array(recentDisplayedComments.suffix(5))
        default:
            break
        }
    }

    private func scheduleLLMIfNeeded(for event: PresentationEvent) {
        guard event.kind == .speechPartial || event.kind == .speechFinal || event.kind == .slideChanged,
              let commentGenerator,
              let descriptor else { return }
        if let lastLLMRequestMs,
           event.timestampMs - lastLLMRequestMs < minimumLLMIntervalMs {
            return
        }

        let transcript = (recentTranscript.map(\.text) + [currentPartialTranscript])
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !transcript.isEmpty || !(currentSlideOCR ?? "").isEmpty else { return }
        lastLLMRequestMs = event.timestampMs
        let context = CommentGenerationContext(
            requestedAtMs: event.timestampMs,
            recentTranscript: transcript,
            currentSlideOCR: currentSlideOCR,
            session: descriptor,
            remainingSeconds: remainingSeconds,
            recentDisplayedComments: recentDisplayedComments
        )
        let hub = self.hub
        let director = self.director
        let timeoutMilliseconds = llmTimeoutMilliseconds

        llmTask?.cancel()
        llmTask = Task {
            do {
                let candidates = try await Self.generateWithTimeout(
                    generator: commentGenerator,
                    context: context,
                    timeoutMilliseconds: timeoutMilliseconds
                )
                try Task.checkCancellation()
                for candidate in candidates {
                    _ = try await hub.emit(
                        kind: .llmCommentCandidate,
                        payload: .commentCandidate(candidate),
                        timestampMs: context.requestedAtMs
                    )
                }
                if let reaction = await director.select(from: candidates, at: context.requestedAtMs) {
                    _ = try await hub.emit(
                        kind: .judgeReaction,
                        payload: .judgeReaction(reaction),
                        timestampMs: context.requestedAtMs
                    )
                }
            } catch {
                // The deterministic rule lane remains active on timeout,
                // cancellation, missing connectivity, and API failures.
            }
        }
    }

    private static func generateWithTimeout(
        generator: any CommentGenerating,
        context: CommentGenerationContext,
        timeoutMilliseconds: Int
    ) async throws -> [CommentCandidate] {
        try await withThrowingTaskGroup(of: [CommentCandidate].self) { group in
            group.addTask {
                try await generator.generateComments(for: context)
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(timeoutMilliseconds))
                throw LivePracticePipelineError.llmTimeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw LivePracticePipelineError.llmTimeout
            }
            return result
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
    case llmTimeout
}
