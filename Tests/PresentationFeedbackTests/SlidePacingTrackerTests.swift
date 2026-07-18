import Foundation
import PresentationContracts
import Testing
@testable import PresentationFeedback

@Test func slidePacingWarnsOnceForLongDwell() {
    var tracker = SlidePacingTracker(configuration: .init(
        longDwellMilliseconds: 1_000,
        rapidChangeWindowMilliseconds: 10_000,
        rapidChangeCount: 5
    ))
    let sessionID = UUID()
    _ = tracker.candidates(for: slideEvent(sessionID: sessionID, timestampMs: 0, id: "one"))

    let first = tracker.candidates(for: timerEvent(sessionID: sessionID, timestampMs: 1_000))
    let repeated = tracker.candidates(for: timerEvent(sessionID: sessionID, timestampMs: 2_000))

    #expect(first.count == 1)
    #expect(first[0].judgeID == .slide)
    #expect(first[0].emotion == .sleepy)
    #expect(first[0].evidenceText == "スライド滞在 1秒")
    #expect(repeated.isEmpty)
}

@Test func slidePacingWarnsWhenChangesAreTooFrequent() {
    var tracker = SlidePacingTracker(configuration: .init(
        longDwellMilliseconds: 60_000,
        rapidChangeWindowMilliseconds: 5_000,
        rapidChangeCount: 3
    ))
    let sessionID = UUID()

    let first = tracker.candidates(for: slideEvent(sessionID: sessionID, timestampMs: 0, id: "one"))
    let second = tracker.candidates(for: slideEvent(sessionID: sessionID, timestampMs: 1_000, id: "two"))
    let third = tracker.candidates(for: slideEvent(sessionID: sessionID, timestampMs: 2_000, id: "three"))
    let coolingDown = tracker.candidates(for: slideEvent(sessionID: sessionID, timestampMs: 3_000, id: "four"))

    #expect(first.isEmpty)
    #expect(second.isEmpty)
    #expect(third.count == 1)
    #expect(third[0].emotion == .panic)
    #expect(coolingDown.isEmpty)
}

private func slideEvent(sessionID: UUID, timestampMs: Int64, id: String) -> PresentationEvent {
    PresentationEvent(
        sessionID: sessionID,
        timestampMs: timestampMs,
        kind: .slideChanged,
        payload: .slideChange(SlideChange(slideID: id))
    )
}

private func timerEvent(sessionID: UUID, timestampMs: Int64) -> PresentationEvent {
    PresentationEvent(
        sessionID: sessionID,
        timestampMs: timestampMs,
        kind: .timerUpdated,
        payload: .timer(TimerUpdate(
            elapsedSeconds: Int(timestampMs / 1_000),
            remainingSeconds: 0
        ))
    )
}
