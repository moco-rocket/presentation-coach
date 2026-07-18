import AppKit
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

@Test func judgeArtworkSheetMapsJudgesAndEmotionsToExpectedCells() {
    let tempoIdle = JudgeArtworkSheet.normalizedRect(for: .tempo, emotion: .idle)
    let audienceSleepy = JudgeArtworkSheet.normalizedRect(for: .audience, emotion: .sleepy)

    #expect(tempoIdle == CGRect(x: 0, y: 0.75, width: 0.2, height: 0.25))
    #expect(audienceSleepy == CGRect(x: 0.8, y: 0, width: 0.2, height: 0.25))
    #expect(
        JudgeArtworkSheet.normalizedRect(for: .tempo, emotion: .happy)
            == JudgeArtworkSheet.normalizedRect(for: .tempo, emotion: .impressed)
    )
    #expect(
        JudgeArtworkSheet.normalizedRect(for: .clarity, emotion: .confused)
            == JudgeArtworkSheet.normalizedRect(for: .clarity, emotion: .panic)
    )
}

@MainActor
@Test func bundledJudgeArtworkSheetLoadsForEveryJudge() {
    for judgeID in JudgeID.allCases {
        #expect(JudgeArtworkSheet.texture(for: judgeID, emotion: .idle) != nil)
    }
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
@Test func overlayPanelAndHostedContentAreTransparent() {
    let controller = OverlayPanelController(viewModel: OverlayViewModel(), screen: nil)

    #expect(controller.panel.isOpaque == false)
    #expect(controller.panel.backgroundColor == .clear)
    #expect(controller.panel.contentView?.isOpaque == false)
    #expect(controller.panel.contentView?.layer?.backgroundColor == NSColor.clear.cgColor)
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

@MainActor
@Test func fixtureTimelineCanDriveOverlayViewModel() throws {
    let manifests = try JudgeManifestLoader.bundled()
    let viewModel = OverlayViewModel(
        manifests: manifests,
        automaticallyDismissReactions: false
    )
    let sessionID = UUID()
    let reaction = JudgeReaction(
        candidateID: UUID(),
        judgeID: .clarity,
        text: "今の説明、すっと入った！",
        emotion: .impressed,
        source: .llm,
        durationMs: 1_800
    )
    let timeline = FixtureTimeline(events: [
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 0,
            kind: .sessionStarted,
            payload: .session(SessionDescriptor(
                title: "UI統合テスト",
                goal: "オーバーレイを確認する",
                audience: "開発者",
                plannedDurationSeconds: 60
            ))
        ),
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 100,
            kind: .judgeReaction,
            payload: .judgeReaction(reaction)
        )
    ])

    timeline.replayImmediately { viewModel.consume($0) }

    #expect(viewModel.isSessionRunning)
    #expect(viewModel.activeReaction == reaction)
    #expect(viewModel.judges.first(where: { $0.id == .clarity })?.emotion == .impressed)
}

@MainActor
@Test func fixtureTimelineSchedulesEventsOnMainRunLoop() async throws {
    let sessionID = UUID()
    let events = [
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 0,
            kind: .timerUpdated,
            payload: .timer(TimerUpdate(elapsedSeconds: 0, remainingSeconds: 60))
        ),
        PresentationEvent(
            sessionID: sessionID,
            timestampMs: 20,
            kind: .timerUpdated,
            payload: .timer(TimerUpdate(elapsedSeconds: 1, remainingSeconds: 59))
        )
    ]
    let timeline = FixtureTimeline(events: events)
    var received: [PresentationEvent] = []

    try timeline.play { received.append($0) }
    try await Task.sleep(for: .milliseconds(80))
    timeline.stop()

    #expect(received == events)
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
