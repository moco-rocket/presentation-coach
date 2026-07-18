import Foundation
import PresentationContracts
import Testing
@testable import PresentationOverlay

@Test func bundledJudgeManifestsLoadInStageOrder() throws {
    let manifests = try JudgeManifestLoader.bundled()

    #expect(manifests.map(\.id) == [.tempo, .clarity, .slide, .audience])
    #expect(Set(manifests.map(\.stageSlot)).count == 4)
    #expect(manifests.allSatisfy { $0.animations[.idle] != nil })
}

@Test func judgeManifestRoundTripsThroughJSON() throws {
    let manifest = try #require(JudgeManifestLoader.bundled().first)
    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(JudgeManifest.self, from: data)

    #expect(decoded == manifest)
}

@MainActor
@Test func viewModelReflectsJudgeReactionAndTimer() throws {
    let manifests = try JudgeManifestLoader.bundled()
    let viewModel = OverlayViewModel(
        manifests: manifests,
        automaticallyDismissReactions: false
    )
    let sessionID = UUID()
    let reaction = JudgeReaction(
        candidateID: UUID(),
        judgeID: .audience,
        text: "その数字、比較対象もほしい！",
        emotion: .curious,
        source: .llm,
        durationMs: 2_200
    )

    viewModel.consume(PresentationEvent(
        sessionID: sessionID,
        timestampMs: 1_000,
        kind: .timerUpdated,
        payload: .timer(TimerUpdate(elapsedSeconds: 60, remainingSeconds: 240))
    ))
    viewModel.consume(PresentationEvent(
        sessionID: sessionID,
        timestampMs: 1_100,
        kind: .judgeReaction,
        payload: .judgeReaction(reaction)
    ))

    #expect(viewModel.timer?.remainingSeconds == 240)
    #expect(viewModel.activeReaction == reaction)
    #expect(viewModel.judges.first(where: { $0.id == .audience })?.emotion == .curious)

    viewModel.clearReaction()
    #expect(viewModel.activeReaction == nil)
    #expect(viewModel.judges.allSatisfy { $0.emotion == .idle })
}

@MainActor
@Test func fixtureTimelineParsesJSONLinesAndReplaysInTimestampOrder() throws {
    let sessionID = UUID()
    let later = makeReactionEvent(
        sessionID: sessionID,
        timestampMs: 1_500,
        judgeID: .clarity,
        text: "ここ、ひと言でまとめよう！"
    )
    let earlier = makeReactionEvent(
        sessionID: sessionID,
        timestampMs: 1_000,
        judgeID: .tempo,
        text: "いい間だね！"
    )
    let encoder = JSONEncoder()
    let jsonLines = try [later, earlier]
        .map { try String(decoding: encoder.encode($0), as: UTF8.self) }
        .joined(separator: "\n")

    let timeline = try FixtureTimeline(jsonLines: jsonLines)
    var replayed: [PresentationEvent] = []
    timeline.replayImmediately { replayed.append($0) }

    #expect(replayed.map(\.timestampMs) == [1_000, 1_500])
    #expect(replayed.map(\.kind) == [.judgeReaction, .judgeReaction])
}

@MainActor
@Test func fixtureTimelineRejectsInvalidPlaybackSpeed() throws {
    let timeline = FixtureTimeline(events: [])
    #expect(throws: FixtureTimelineError.invalidSpeed) {
        try timeline.play(speed: 0) { _ in }
    }
}

@MainActor
@Test func checkedInUIDemoFixtureIsDecodable() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixtureURL = packageRoot.appendingPathComponent("Fixtures/Sessions/ui-demo.jsonl")
    let timeline = try FixtureTimeline(contentsOf: fixtureURL)
    let reactions = timeline.events.filter { $0.kind == .judgeReaction }

    #expect(timeline.events.count == 6)
    #expect(reactions.count == 4)
}

private func makeReactionEvent(
    sessionID: UUID,
    timestampMs: Int64,
    judgeID: JudgeID,
    text: String
) -> PresentationEvent {
    PresentationEvent(
        sessionID: sessionID,
        timestampMs: timestampMs,
        kind: .judgeReaction,
        payload: .judgeReaction(JudgeReaction(
            candidateID: UUID(),
            judgeID: judgeID,
            text: text,
            emotion: .happy,
            source: .rule,
            durationMs: 1_800
        ))
    )
}
