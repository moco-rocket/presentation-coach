import Foundation
import Testing
@testable import PresentationContracts

@Test func eventRoundTripsThroughJSON() throws {
    let sessionID = UUID()
    let candidate = CommentCandidate(
        judgeID: .audience,
        text: "その数字、比較対象もほしい！",
        emotion: .curious,
        priority: 72,
        confidence: 0.86,
        evidenceText: "導入コストを30%削減できます",
        source: .llm,
        createdAtMs: 1_000,
        expiresAtMs: 4_000
    )
    let event = PresentationEvent(
        sessionID: sessionID,
        timestampMs: 1_000,
        kind: .llmCommentCandidate,
        payload: .commentCandidate(candidate)
    )

    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(PresentationEvent.self, from: data)

    #expect(decoded == event)
}
