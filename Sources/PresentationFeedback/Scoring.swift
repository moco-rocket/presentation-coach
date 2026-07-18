import Foundation
import PresentationContracts

public struct SessionEvaluationMetrics: Equatable, Sendable {
    public var plannedDurationSeconds: Int
    public var actualDurationSeconds: Int
    public var spokenDurationSeconds: Int
    public var fillerCount: Int
    public var longSilenceCount: Int
    public var averageCharactersPerSecond: Double
    public var slideCount: Int
    public var denseSlideCount: Int
    public var structureMarkerCount: Int
    public var audienceEngagementCueCount: Int

    public init(
        plannedDurationSeconds: Int,
        actualDurationSeconds: Int,
        spokenDurationSeconds: Int,
        fillerCount: Int,
        longSilenceCount: Int,
        averageCharactersPerSecond: Double,
        slideCount: Int,
        denseSlideCount: Int,
        structureMarkerCount: Int,
        audienceEngagementCueCount: Int
    ) {
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualDurationSeconds = actualDurationSeconds
        self.spokenDurationSeconds = spokenDurationSeconds
        self.fillerCount = fillerCount
        self.longSilenceCount = longSilenceCount
        self.averageCharactersPerSecond = averageCharactersPerSecond
        self.slideCount = slideCount
        self.denseSlideCount = denseSlideCount
        self.structureMarkerCount = structureMarkerCount
        self.audienceEngagementCueCount = audienceEngagementCueCount
    }
}

public struct PresentationScoreReport: Equatable, Sendable {
    public var categories: [ScoreUpdate]

    public init(categories: [ScoreUpdate]) {
        self.categories = categories
    }

    public var totalScore: Double { categories.reduce(0) { $0 + $1.score } }
    public var maximumScore: Double { categories.reduce(0) { $0 + $1.maximumScore } }
}

/// A transparent baseline scorer. A later LLM evaluator may add qualitative
/// evidence, but does not need to replace these reproducible measurements.
public struct PresentationScorer: Sendable {
    public init() {}

    public func score(_ metrics: SessionEvaluationMetrics) -> PresentationScoreReport {
        let minutesSpoken = max(Double(metrics.spokenDurationSeconds) / 60, 0.5)
        let fillersPerMinute = Double(max(0, metrics.fillerCount)) / minutesSpoken
        let clarity = clamp(20 - fillersPerMinute * 1.5, maximum: 20)

        let targetRate = 5.5
        let ratePenalty = abs(metrics.averageCharactersPerSecond - targetRate) * 2
        let silencePenalty = Double(max(0, metrics.longSilenceCount)) * 1.25
        let tempo = clamp(20 - ratePenalty - silencePenalty, maximum: 20)

        let planned = max(1, metrics.plannedDurationSeconds)
        let durationErrorRatio = abs(Double(metrics.actualDurationSeconds - planned)) / Double(planned)
        let completion = clamp(10 - durationErrorRatio * 20, maximum: 10)

        let denseRatio = metrics.slideCount > 0
            ? Double(max(0, metrics.denseSlideCount)) / Double(metrics.slideCount)
            : 0
        let slide = clamp(15 - denseRatio * 10, maximum: 15)

        let structure = clamp(10 + Double(max(0, metrics.structureMarkerCount)) * 5, maximum: 25)
        let engagement = clamp(Double(max(0, metrics.audienceEngagementCueCount)) * 2.5, maximum: 10)

        return PresentationScoreReport(categories: [
            ScoreUpdate(
                category: "構成・内容",
                score: rounded(structure),
                maximumScore: 25,
                evidence: ["構成を示す表現 \(max(0, metrics.structureMarkerCount))回"]
            ),
            ScoreUpdate(
                category: "話し方の明瞭さ",
                score: rounded(clarity),
                maximumScore: 20,
                evidence: [String(format: "フィラー %.1f回/分", fillersPerMinute)]
            ),
            ScoreUpdate(
                category: "テンポ・時間配分",
                score: rounded(tempo),
                maximumScore: 20,
                evidence: [
                    String(format: "平均話速 %.1f文字/秒", metrics.averageCharactersPerSecond),
                    "長い無音 \(max(0, metrics.longSilenceCount))回"
                ]
            ),
            ScoreUpdate(
                category: "スライド品質",
                score: rounded(slide),
                maximumScore: 15,
                evidence: ["高密度スライド \(max(0, metrics.denseSlideCount))/\(max(0, metrics.slideCount))枚"]
            ),
            ScoreUpdate(
                category: "聴衆への働きかけ",
                score: rounded(engagement),
                maximumScore: 10,
                evidence: ["問いかけ・参加促進 \(max(0, metrics.audienceEngagementCueCount))回"]
            ),
            ScoreUpdate(
                category: "発表の完成度",
                score: rounded(completion),
                maximumScore: 10,
                evidence: ["予定 \(planned)秒 / 実績 \(max(0, metrics.actualDurationSeconds))秒"]
            )
        ])
    }

    private func clamp(_ value: Double, maximum: Double) -> Double {
        min(maximum, max(0, value))
    }

    private func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
