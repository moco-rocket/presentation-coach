import Foundation
import PresentationContracts
import Testing
@testable import PresentationCapture

@Test func recordsAndReadsEvents() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("events.jsonl")
    let recorder = JSONLEventRecorder(url: url)
    let sessionID = UUID()
    let event = PresentationEvent(
        sessionID: sessionID,
        timestampMs: 0,
        kind: .sessionStopped,
        payload: .none
    )

    try await recorder.append(event)
    try await recorder.close()

    #expect(try JSONLEventReader.read(from: url) == [event])
}
