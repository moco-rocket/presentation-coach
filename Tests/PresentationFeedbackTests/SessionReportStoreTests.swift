import Foundation
import PresentationContracts
import Testing
@testable import PresentationFeedback

@Test func reportStorePersistsListsAndExportsMarkdown() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = SessionReportStore(directory: directory)
    let evidence = SessionEvidence(timestampMs: 12_000, kind: .transcript, text: "結論から説明します")
    let metrics = SessionEvaluationMetrics(
        plannedDurationSeconds: 60,
        actualDurationSeconds: 55,
        spokenDurationSeconds: 40,
        fillerCount: 1,
        longSilenceCount: 0,
        averageCharactersPerSecond: 5,
        slideCount: 3,
        denseSlideCount: 0,
        structureMarkerCount: 2,
        audienceEngagementCueCount: 1
    )
    let report = SessionReport(
        session: SessionDescriptor(title: "企画発表", goal: "承認", audience: "審査員", plannedDurationSeconds: 60),
        metrics: metrics,
        score: PresentationScorer().score(metrics),
        startedAtMs: 0,
        endedAtMs: 55_000,
        evidence: [evidence],
        qualitativeEvaluation: QualitativeEvaluation(
            strengths: [EvaluatedInsight(text: "結論が明確です", evidence: evidence)],
            improvements: [EvaluatedInsight(text: "例を足しましょう", evidence: evidence)],
            nextActions: [EvaluatedInsight(text: "冒頭を練習しましょう", evidence: evidence)]
        )
    )
    let stored = StoredSessionReport(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        report: report
    )

    let savedURL = try store.save(stored)
    let loaded = try store.loadAll()
    let markdown = store.markdown(for: stored)

    #expect(savedURL.lastPathComponent == "00000000-0000-0000-0000-000000000001.report.json")
    #expect(loaded == [stored])
    #expect(markdown.contains("# 企画発表"))
    #expect(markdown.contains("結論が明確です"))
    #expect(markdown.contains("00:12"))
}

@Test func reportStoreReturnsEmptyHistoryBeforeFirstPractice() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    #expect(try SessionReportStore(directory: directory).loadAll().isEmpty)
}
