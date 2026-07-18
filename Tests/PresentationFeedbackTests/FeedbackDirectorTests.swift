import Foundation
import Testing
import PresentationContracts
@testable import PresentationFeedback

@Test func directorChoosesHighestPriorityEligibleCandidate() async {
    let director = FeedbackDirector()
    let rule = candidate(id: 1, judge: .tempo, text: "速い！", priority: 80, source: .rule)
    let llm = candidate(id: 2, judge: .audience, text: "比較対象もほしい！", priority: 90, source: .llm)

    let reaction = await director.select(from: [rule, llm], at: 1_500)

    #expect(reaction?.candidateID == llm.id)
    #expect(reaction?.source == .llm)
}

@Test func directorDropsExpiredAndFutureCandidates() async {
    let director = FeedbackDirector()
    let expired = candidate(id: 1, judge: .tempo, text: "古い", priority: 100, createdAt: 0, expiresAt: 1_000)
    let future = candidate(id: 2, judge: .clarity, text: "未来", priority: 100, createdAt: 2_000, expiresAt: 3_000)

    let reaction = await director.select(from: [expired, future], at: 1_000)
    #expect(reaction == nil)
}

@Test func directorEnforcesPerJudgeCooldownWithoutBlockingOtherJudge() async {
    let director = FeedbackDirector(configuration: .init(judgeCooldownMilliseconds: 6_000))
    let first = candidate(id: 1, judge: .tempo, text: "最初", priority: 80)
    let second = candidate(id: 2, judge: .tempo, text: "二回目", priority: 90, createdAt: 2_000, expiresAt: 20_000)
    let otherJudge = candidate(id: 3, judge: .slide, text: "別の審査員", priority: 70, createdAt: 2_000, expiresAt: 20_000)

    let firstReaction = await director.select(from: [first], at: 1_000)
    let secondReaction = await director.select(from: [second, otherJudge], at: 2_000)
    let afterCooldown = await director.select(from: [second], at: 7_000)

    #expect(firstReaction?.judgeID == .tempo)
    #expect(secondReaction?.judgeID == .slide)
    #expect(afterCooldown?.judgeID == .tempo)
}

@Test func directorSuppressesDuplicateTextAndTruncatesLongComment() async {
    let director = FeedbackDirector(configuration: .init(
        judgeCooldownMilliseconds: 0,
        duplicateWindowMilliseconds: 30_000,
        maximumCommentCharacters: 10
    ))
    let original = candidate(id: 1, judge: .tempo, text: "これはかなり長いコメントなので短くなります", priority: 90)
    let duplicate = candidate(id: 2, judge: .audience, text: "これはかなり長いコメントなので短くなります！", priority: 95, createdAt: 2_000, expiresAt: 20_000)

    let first = await director.select(from: [original], at: 1_000)
    let second = await director.select(from: [duplicate], at: 2_000)

    #expect(first?.text.count == 10)
    #expect(first?.text.last == "…")
    #expect(second == nil)
}

private func candidate(
    id: Int,
    judge: JudgeID,
    text: String,
    priority: Int,
    source: CommentSource = .rule,
    createdAt: Int64 = 0,
    expiresAt: Int64 = 10_000
) -> CommentCandidate {
    CommentCandidate(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
        judgeID: judge,
        text: text,
        emotion: .curious,
        priority: priority,
        confidence: 0.9,
        source: source,
        createdAtMs: createdAt,
        expiresAtMs: expiresAt
    )
}
