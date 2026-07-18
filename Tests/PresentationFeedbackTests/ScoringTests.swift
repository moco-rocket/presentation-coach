import Testing
@testable import PresentationFeedback

@Test func scorerProducesSixCategoriesTotalingOneHundredMaximum() {
    let metrics = SessionEvaluationMetrics(
        plannedDurationSeconds: 600,
        actualDurationSeconds: 600,
        spokenDurationSeconds: 480,
        fillerCount: 0,
        longSilenceCount: 0,
        averageCharactersPerSecond: 5.5,
        slideCount: 8,
        denseSlideCount: 0,
        structureMarkerCount: 3,
        audienceEngagementCueCount: 4
    )

    let report = PresentationScorer().score(metrics)

    #expect(report.categories.count == 6)
    #expect(report.maximumScore == 100)
    #expect(report.totalScore == 100)
}

@Test func scorerPenalizesMeasuredPresentationProblemsAndKeepsBounds() {
    let weak = SessionEvaluationMetrics(
        plannedDurationSeconds: 300,
        actualDurationSeconds: 900,
        spokenDurationSeconds: 60,
        fillerCount: 100,
        longSilenceCount: 30,
        averageCharactersPerSecond: 20,
        slideCount: 4,
        denseSlideCount: 10,
        structureMarkerCount: -1,
        audienceEngagementCueCount: -1
    )

    let report = PresentationScorer().score(weak)

    #expect(report.totalScore >= 0)
    #expect(report.totalScore <= report.maximumScore)
    #expect(report.categories.allSatisfy { $0.score >= 0 && $0.score <= $0.maximumScore })
    #expect(report.categories.allSatisfy { !$0.evidence.isEmpty })
}
