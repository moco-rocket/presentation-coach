import Foundation
import PresentationContracts
import Testing
@testable import PresentationCapture

@Test func sessionHubPublishesAndRecordsLifecycle() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("session.jsonl")
    let hub = SessionEventHub(recordingURL: url)
    let stream = await hub.events()
    var iterator = stream.makeAsyncIterator()

    let descriptor = SessionDescriptor(
        title: "新サービス提案",
        goal: "承認を得る",
        audience: "審査員",
        plannedDurationSeconds: 300
    )
    let started = try await hub.start(descriptor: descriptor)
    let stopped = try await hub.stop()

    #expect(await iterator.next() == started)
    #expect(await iterator.next() == stopped)

    let recorded = try JSONLEventReader.read(from: url)
    #expect(recorded == [started, stopped])
}
