import Foundation
import PresentationContracts
import Testing
@testable import PresentationFeedback

@Test func reportBuilderAggregatesRecordedEvidence() throws {
    let sessionID = UUID()
    let events = [
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 0,
            kind: .sessionStarted,
            payload: .session(SessionDescriptor(
                title: "新企画", goal: "承認", audience: "審査員", plannedDurationSeconds: 60
            ))
        ),
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 3_000,
            kind: .audioMetric,
            payload: .audioMetric(AudioMetric(
                rmsDB: -80, peakDB: -70, isSpeech: false, silenceDurationMs: 3_000
            ))
        ),
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 10_000,
            kind: .speechFinal,
            payload: .speech(SpeechSegment(
                text: "えーと、まず結論です。どうでしょうか？",
                startedAtMs: 4_000,
                endedAtMs: 10_000
            ))
        ),
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 12_000,
            kind: .slideChanged,
            payload: .slideChange(SlideChange(
                slideID: "slide-1", ocrText: "大量の文字", textDensity: 0.8
            ))
        ),
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 60_000,
            kind: .sessionStopped,
            payload: .none
        )
    ]

    let report = try SessionReportBuilder.build(from: events)

    #expect(report.session.title == "新企画")
    #expect(report.metrics.actualDurationSeconds == 60)
    #expect(report.metrics.spokenDurationSeconds == 6)
    #expect(report.metrics.fillerCount == 1)
    #expect(report.metrics.longSilenceCount == 1)
    #expect(report.metrics.slideCount == 1)
    #expect(report.metrics.denseSlideCount == 1)
    #expect(report.metrics.structureMarkerCount == 2)
    #expect(report.metrics.audienceEngagementCueCount == 2)
    #expect(report.score.categories.count == 6)
    #expect(report.score.maximumScore == 100)
}

@Test func reportBuilderRequiresSessionStart() {
    #expect(throws: SessionReportBuilderError.missingSessionStart) {
        try SessionReportBuilder.build(from: [])
    }
}

@Test func reportBuilderUsesLatestPartialWhenRecognizerHasNotFinalized() throws {
    let sessionID = UUID()
    let events = [
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 0,
            kind: .sessionStarted,
            payload: .session(SessionDescriptor(
                title: "短い練習", goal: "", audience: "", plannedDurationSeconds: 10
            ))
        ),
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 2_000,
            kind: .speechPartial,
            payload: .speech(SpeechSegment(text: "まず結論です", startedAtMs: 500))
        ),
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 4_000,
            kind: .sessionStopped,
            payload: .none
        )
    ]

    let report = try SessionReportBuilder.build(from: events)

    #expect(report.metrics.spokenDurationSeconds == 3)
    #expect(report.metrics.structureMarkerCount == 2)
}
