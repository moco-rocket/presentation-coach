import Foundation
import PresentationCapture
import PresentationContracts
import PresentationFeedback
import Testing
@testable import PresentationApp

private actor EventCollector {
    var events: [PresentationEvent] = []
    private var waiters: [(PresentationEventKind, CheckedContinuation<Void, Never>)] = []

    func append(_ event: PresentationEvent) {
        events.append(event)
        let matching = waiters.filter { $0.0 == event.kind }
        waiters.removeAll { $0.0 == event.kind }
        matching.forEach { $0.1.resume() }
    }

    func wait(for kind: PresentationEventKind) async {
        guard !events.contains(where: { $0.kind == kind }) else { return }
        await withCheckedContinuation { continuation in
            waiters.append((kind, continuation))
        }
    }
}

@Test func livePipelineRecordsRulesAndJudgeReaction() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recordingURL = directory.appendingPathComponent("live.jsonl")
    let sessionID = UUID()
    let collector = EventCollector()
    let pipeline = LivePracticePipeline(sessionID: sessionID, recordingURL: recordingURL) { event in
        await collector.append(event)
    }

    try await pipeline.start(descriptor: SessionDescriptor(
        title: "ライブテスト",
        goal: "接続確認",
        audience: "開発者",
        plannedDurationSeconds: 60
    ))
    try await pipeline.ingest(PresentationEvent(
        sessionID: sessionID,
        timestampMs: 500,
        kind: .audioMetric,
        payload: .audioMetric(AudioMetric(
            rmsDB: -40,
            peakDB: -10,
            isSpeech: true,
            silenceDurationMs: 0
        ))
    ))
    try await pipeline.stop()

    let recorded = try JSONLEventReader.read(from: recordingURL)
    let kinds = recorded.map(\.kind)
    #expect(kinds.contains(.sessionStarted))
    #expect(kinds.contains(.audioMetric))
    #expect(kinds.contains(.ruleCommentCandidate))
    #expect(kinds.contains(.judgeReaction))
    #expect(kinds.last == .sessionStopped)
    #expect(await collector.events.map(\.kind) == kinds)
}

@Test func livePipelineRejectsAnotherSession() async throws {
    let pipeline = LivePracticePipeline { _ in }
    try await pipeline.start(descriptor: SessionDescriptor(
        title: "テスト", goal: "", audience: "", plannedDurationSeconds: 0
    ))

    await #expect(throws: LivePracticePipelineError.sessionMismatch) {
        try await pipeline.ingest(PresentationEvent(
            sessionID: UUID(),
            timestampMs: 0,
            kind: .timerUpdated,
            payload: .timer(TimerUpdate(elapsedSeconds: 0, remainingSeconds: 0))
        ))
    }
    try await pipeline.stop()
}

private struct ImmediateCommentGenerator: CommentGenerating {
    func generateComments(for context: CommentGenerationContext) async throws -> [CommentCandidate] {
        [CommentCandidate(
            judgeID: .clarity,
            text: "要点が伝わった！",
            emotion: .happy,
            priority: 75,
            confidence: 0.9,
            evidenceText: context.currentSlideOCR,
            source: .llm,
            createdAtMs: context.requestedAtMs,
            expiresAtMs: context.requestedAtMs + 3_000
        )]
    }
}

private struct FailingCommentGenerator: CommentGenerating {
    struct Failure: Error {}
    func generateComments(for context: CommentGenerationContext) async throws -> [CommentCandidate] {
        throw Failure()
    }
}

private struct HangingCommentGenerator: CommentGenerating {
    func generateComments(for context: CommentGenerationContext) async throws -> [CommentCandidate] {
        try await Task.sleep(for: .seconds(30))
        return []
    }
}

@Test func livePipelinePublishesLLMCommentsFromSlideContext() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recordingURL = directory.appendingPathComponent("llm.jsonl")
    let sessionID = UUID()
    let collector = EventCollector()
    let pipeline = LivePracticePipeline(
        sessionID: sessionID,
        recordingURL: recordingURL,
        commentGenerator: ImmediateCommentGenerator(),
        minimumLLMIntervalMs: 0
    ) { event in
        await collector.append(event)
    }
    try await pipeline.start(descriptor: SessionDescriptor(
        title: "ライブテスト", goal: "接続確認", audience: "開発者", plannedDurationSeconds: 60
    ))
    try await pipeline.ingest(PresentationEvent(
        sessionID: sessionID,
        timestampMs: 100,
        kind: .slideChanged,
        payload: .slideChange(SlideChange(slideID: "slide-1", ocrText: "大事な結論"))
    ))
    await collector.wait(for: .llmCommentCandidate)
    try await pipeline.stop()

    let recorded = try JSONLEventReader.read(from: recordingURL)
    #expect(recorded.contains { $0.kind == .llmCommentCandidate })
    #expect(recorded.contains {
        guard case let .judgeReaction(reaction) = $0.payload else { return false }
        return reaction.source == .llm
    })
}

@Test func livePipelineKeepsRuleLaneWhenLLMFails() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recordingURL = directory.appendingPathComponent("fallback.jsonl")
    let sessionID = UUID()
    let pipeline = LivePracticePipeline(
        sessionID: sessionID,
        recordingURL: recordingURL,
        commentGenerator: FailingCommentGenerator(),
        minimumLLMIntervalMs: 0
    ) { _ in }
    try await pipeline.start(descriptor: SessionDescriptor(
        title: "フォールバック", goal: "", audience: "", plannedDurationSeconds: 60
    ))
    try await pipeline.ingest(PresentationEvent(
        sessionID: sessionID,
        timestampMs: 100,
        kind: .audioMetric,
        payload: .audioMetric(AudioMetric(rmsDB: -45, peakDB: -10, isSpeech: true, silenceDurationMs: 0))
    ))
    try await pipeline.ingest(PresentationEvent(
        sessionID: sessionID,
        timestampMs: 200,
        kind: .slideChanged,
        payload: .slideChange(SlideChange(slideID: "slide-1", ocrText: "接続失敗でも継続"))
    ))
    try await Task.sleep(for: .milliseconds(30))
    try await pipeline.stop()

    let recorded = try JSONLEventReader.read(from: recordingURL)
    #expect(recorded.contains { $0.kind == .ruleCommentCandidate })
    #expect(!recorded.contains { $0.kind == .llmCommentCandidate })
}

@Test func livePipelineTimesOutLLMWithoutBlockingStop() async throws {
    let sessionID = UUID()
    let pipeline = LivePracticePipeline(
        sessionID: sessionID,
        commentGenerator: HangingCommentGenerator(),
        minimumLLMIntervalMs: 0,
        llmTimeoutMilliseconds: 10
    ) { _ in }
    try await pipeline.start(descriptor: SessionDescriptor(
        title: "タイムアウト", goal: "", audience: "", plannedDurationSeconds: 60
    ))
    try await pipeline.ingest(PresentationEvent(
        sessionID: sessionID,
        timestampMs: 100,
        kind: .slideChanged,
        payload: .slideChange(SlideChange(slideID: "slide-1", ocrText: "応答待ち"))
    ))
    try await Task.sleep(for: .milliseconds(30))

    try await pipeline.stop()
}
