import Foundation
import Testing
import PresentationContracts
@testable import PresentationFeedback

@Test func longSilenceProducesDeterministicTempoCandidate() {
    let eventID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    let event = PresentationEvent(
        id: eventID,
        sessionID: UUID(),
        timestampMs: 10_000,
        kind: .audioMetric,
        payload: .audioMetric(AudioMetric(rmsDB: -70, peakDB: -60, isSpeech: false, silenceDurationMs: 3_200))
    )
    let engine = RuleEngine()

    let first = engine.candidates(for: event)
    let second = engine.candidates(for: event)

    #expect(first == second)
    #expect(first.count == 1)
    #expect(first.first?.judgeID == .tempo)
    #expect(first.first?.source == .rule)
    #expect(first.first?.evidenceText == "無音 3200ms")
    #expect(first.first?.createdAtMs == 10_000)
    #expect(first.first?.expiresAtMs == 13_000)
}

@Test func finalSpeechCanProduceSpeedAndFillerFeedbackInPriorityOrder() {
    let segment = SpeechSegment(
        text: "えーとあのーここから重要な説明をかなり速く進めていきます",
        startedAtMs: 1_000,
        endedAtMs: 3_000,
        confidence: 0.95
    )
    let event = PresentationEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
        sessionID: UUID(),
        timestampMs: 3_000,
        kind: .speechFinal,
        payload: .speech(segment)
    )

    let candidates = RuleEngine().candidates(for: event)

    #expect(candidates.count == 2)
    #expect(candidates[0].judgeID == .tempo)
    #expect(candidates[0].priority > candidates[1].priority)
    #expect(candidates[1].judgeID == .clarity)
}

@Test func denseSlideTriggersOnlyAtConfiguredThreshold() {
    let engine = RuleEngine(configuration: .init(denseSlideThreshold: 0.8))
    let sessionID = UUID()
    let sparse = PresentationEvent(
        sessionID: sessionID,
        timestampMs: 1_000,
        kind: .slideChanged,
        payload: .slideChange(SlideChange(slideID: "1", textDensity: 0.79))
    )
    let dense = PresentationEvent(
        sessionID: sessionID,
        timestampMs: 2_000,
        kind: .slideChanged,
        payload: .slideChange(SlideChange(slideID: "2", textDensity: 0.8))
    )

    #expect(engine.candidates(for: sparse).isEmpty)
    #expect(engine.candidates(for: dense).first?.judgeID == .slide)
}

@Test func partialSpeechDoesNotTriggerFinalSpeechRules() {
    let event = PresentationEvent(
        sessionID: UUID(),
        timestampMs: 2_000,
        kind: .speechPartial,
        payload: .speech(SpeechSegment(text: "えーと、えーと", startedAtMs: 0, endedAtMs: 1_000))
    )
    #expect(RuleEngine().candidates(for: event).isEmpty)
}
