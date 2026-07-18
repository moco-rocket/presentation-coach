import Foundation
import PresentationContracts
import Testing
@testable import PresentationFeedback

private struct ReportStubLoader: HTTPDataLoading {
    var handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    func data(for request: URLRequest) async throws -> (Data, URLResponse) { try await handler(request) }
}

@Test func reportEvaluatorMapsModelEvidenceIndicesToRecordedTimestamps() async throws {
    let output = #"{"strengths":[{"text":"結論が明確です","evidenceIndex":0}],"improvements":[{"text":"スライドを短くしましょう","evidenceIndex":1}],"nextActions":[{"text":"冒頭を30秒で練習しましょう","evidenceIndex":0}]}"#
    let response = #"{"output":[{"content":[{"type":"output_text","text":""#
        + output.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        + #""}]}]}"#
    let loader = ReportStubLoader { request in
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-5-mini")
        return (
            Data(response.utf8),
            HTTPURLResponse(url: try #require(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
    let evaluator = try OpenAIReportEvaluator(apiKey: "test-token", loader: loader)
    let first = SessionEvidence(timestampMs: 3_000, kind: .transcript, text: "結論から説明します")
    let second = SessionEvidence(timestampMs: 8_000, kind: .slide, text: "文字が多いスライド")
    let report = SessionReport(
        session: SessionDescriptor(title: "発表", goal: "", audience: "", plannedDurationSeconds: 60),
        metrics: emptyMetrics,
        score: PresentationScorer().score(emptyMetrics),
        startedAtMs: 0,
        endedAtMs: 10_000,
        evidence: [first, second]
    )

    let evaluation = try await evaluator.evaluate(report)

    #expect(evaluation.strengths.first?.evidence.timestampMs == 3_000)
    #expect(evaluation.improvements.first?.evidence.timestampMs == 8_000)
    #expect(evaluation.nextActions.first?.evidence.id == first.id)
}

@Test func reportEvaluatorRequiresRecordedEvidence() async throws {
    let evaluator = try OpenAIReportEvaluator(apiKey: "test-token")
    let report = SessionReport(
        session: SessionDescriptor(title: "", goal: "", audience: "", plannedDurationSeconds: 0),
        metrics: emptyMetrics,
        score: PresentationScorer().score(emptyMetrics),
        startedAtMs: 0,
        endedAtMs: 0
    )

    await #expect(throws: OpenAIReportEvaluatorError.insufficientEvidence) {
        try await evaluator.evaluate(report)
    }
}

private let emptyMetrics = SessionEvaluationMetrics(
    plannedDurationSeconds: 60,
    actualDurationSeconds: 60,
    spokenDurationSeconds: 0,
    fillerCount: 0,
    longSilenceCount: 0,
    averageCharactersPerSecond: 0,
    slideCount: 0,
    denseSlideCount: 0,
    structureMarkerCount: 0,
    audienceEngagementCueCount: 0
)
