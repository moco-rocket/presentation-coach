import Foundation
import PresentationCapture
import PresentationContracts
import Testing
@testable import PresentationApp

private actor EventCollector {
    var events: [PresentationEvent] = []
    func append(_ event: PresentationEvent) { events.append(event) }
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
