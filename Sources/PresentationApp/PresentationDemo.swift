import Foundation
import PresentationCapture
import PresentationContracts
import PresentationFeedback

struct PresentationDemoResult {
    let judgeID: JudgeID
    let comment: String
    let score: Double
    let maximumScore: Double
    let recordingURL: URL
}

enum PresentationDemo {
    static func run() async throws -> PresentationDemoResult {
        let recordingURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("session-data", isDirectory: true)
            .appendingPathComponent("demo.jsonl")
        try? FileManager.default.removeItem(at: recordingURL)

        let hub = SessionEventHub(recordingURL: recordingURL)
        let descriptor = SessionDescriptor(
            title: "発表練習アプリ",
            goal: "審査員から開発承認を得る",
            audience: "プロダクト審査員",
            plannedDurationSeconds: 300
        )
        _ = try await hub.start(descriptor: descriptor)

        let speech = SpeechSegment(
            text: "この方式では導入コストを30パーセント削減できます",
            startedAtMs: 500,
            endedAtMs: 1_300,
            confidence: 0.94
        )
        let speechEvent = try await hub.emit(
            kind: .speechFinal,
            payload: .speech(speech),
            timestampMs: 1_300
        )

        let ruleCandidates = RuleEngine().candidates(for: speechEvent)
        let llm = MockCommentGenerator(
            delayMilliseconds: 25,
            comments: [
                MockGeneratedComment(
                    judgeID: .audience,
                    text: "その30%、比較対象もほしい！",
                    emotion: .curious,
                    priority: 88,
                    confidence: 0.91,
                    evidenceText: speech.text
                )
            ]
        )
        let context = CommentGenerationContext(
            requestedAtMs: 1_300,
            recentTranscript: speech.text,
            session: descriptor,
            currentSection: "効果",
            remainingSeconds: 250
        )
        let llmCandidates = try await llm.generateComments(for: context)

        for candidate in ruleCandidates + llmCandidates {
            let kind: PresentationEventKind = candidate.source == .rule
                ? .ruleCommentCandidate
                : .llmCommentCandidate
            _ = try await hub.emit(
                kind: kind,
                payload: .commentCandidate(candidate),
                timestampMs: candidate.createdAtMs
            )
        }

        let director = FeedbackDirector()
        guard let reaction = await director.select(
            from: ruleCandidates + llmCandidates,
            at: 1_400
        ) else {
            throw PresentationDemoError.noReaction
        }
        _ = try await hub.emit(
            kind: .judgeReaction,
            payload: .judgeReaction(reaction),
            timestampMs: 1_400
        )

        let report = PresentationScorer().score(
            SessionEvaluationMetrics(
                plannedDurationSeconds: 300,
                actualDurationSeconds: 302,
                spokenDurationSeconds: 250,
                fillerCount: 3,
                longSilenceCount: 1,
                averageCharactersPerSecond: 5.8,
                slideCount: 8,
                denseSlideCount: 1,
                structureMarkerCount: 3,
                audienceEngagementCueCount: 3
            )
        )
        for score in report.categories {
            _ = try await hub.emit(
                kind: .scoreUpdated,
                payload: .score(score),
                timestampMs: 302_000
            )
        }
        _ = try await hub.stop()

        return PresentationDemoResult(
            judgeID: reaction.judgeID,
            comment: reaction.text,
            score: report.totalScore,
            maximumScore: report.maximumScore,
            recordingURL: recordingURL
        )
    }
}

enum PresentationDemoError: Error {
    case noReaction
}
