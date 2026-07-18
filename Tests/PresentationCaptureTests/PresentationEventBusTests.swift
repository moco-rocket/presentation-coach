import Foundation
import PresentationContracts
import Testing
@testable import PresentationCapture

@Test func broadcastsEventsToSubscriber() async throws {
    let bus = PresentationEventBus()
    let stream = await bus.stream()
    let sessionID = UUID()
    let event = PresentationEvent(
        sessionID: sessionID,
        timestampMs: 1,
        kind: .timerUpdated,
        payload: .timer(TimerUpdate(elapsedSeconds: 1, remainingSeconds: 59))
    )

    await bus.publish(event)
    var iterator = stream.makeAsyncIterator()
    let received = await iterator.next()
    #expect(received == event)
    await bus.finish()
}
