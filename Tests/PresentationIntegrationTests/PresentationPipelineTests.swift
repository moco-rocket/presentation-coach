import Foundation
import PresentationCapture
import PresentationContracts
import PresentationFeedback
import Testing

@Test func ruleAndLLMCandidatesProduceOneRecordedReaction() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("integration.jsonl")
    let hub = SessionEventHub(recordingURL: url)
    let descriptor = SessionDescriptor(
        title: "テスト発表",
        goal: "承認",
        audience: "審査員",
        plannedDurationSeconds: 60
    )
    _ = try await hub.start(descriptor: descriptor)

    let segment = SpeechSegment(
        text: "えーと、えーと、この方法で30%改善します",
        startedAtMs: 100,
        endedAtMs: 900
    )
    let event = try await hub.emit(
        kind: .speechFinal,
        payload: .speech(segment),
        timestampMs: 900
    )
    let rules = RuleEngine().candidates(for: event)
    let llm = MockCommentGenerator(
        delayMilliseconds: 0,
        comments: [
            MockGeneratedComment(
                judgeID: .audience,
                text: "30%の基準を教えて！",
                emotion: .curious,
                priority: 90
            )
        ]
    )
    let generated = try await llm.generateComments(
        for: CommentGenerationContext(
            requestedAtMs: 900,
            recentTranscript: segment.text,
            session: descriptor,
            remainingSeconds: 50
        )
    )
    let director = FeedbackDirector()
    let reaction = await director.select(from: rules + generated, at: 1_000)
    #expect(reaction?.source == .llm)
    #expect(reaction?.judgeID == .audience)

    if let reaction {
        _ = try await hub.emit(
            kind: .judgeReaction,
            payload: .judgeReaction(reaction),
            timestampMs: 1_000
        )
    }
    _ = try await hub.stop()

    let events = try JSONLEventReader.read(from: url)
    #expect(events.filter { $0.kind == .judgeReaction }.count == 1)
}
