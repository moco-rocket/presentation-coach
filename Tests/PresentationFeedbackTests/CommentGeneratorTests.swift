import Testing
import PresentationContracts
@testable import PresentationFeedback

@Test func mockGeneratorCreatesAtMostThreeLLMCandidates() async throws {
    let comments = (0..<4).map { index in
        MockGeneratedComment(
            judgeID: .audience,
            text: "候補\(index)",
            emotion: .curious,
            priority: 70 + index
        )
    }
    let generator = MockCommentGenerator(delayMilliseconds: 1, comments: comments)
    let context = CommentGenerationContext(
        requestedAtMs: 5_000,
        recentTranscript: "導入コストを30%削減できます",
        currentSlideOCR: "導入効果",
        session: SessionDescriptor(title: "新方式", goal: "承認", audience: "経営会議", plannedDurationSeconds: 600),
        currentSection: "効果",
        remainingSeconds: 300
    )

    let first = try await generator.generateComments(for: context)
    let second = try await generator.generateComments(for: context)

    #expect(first == second)
    #expect(first.count == 3)
    #expect(first.allSatisfy { $0.source == .llm })
    #expect(first.allSatisfy { $0.createdAtMs == 5_000 && $0.expiresAtMs == 8_000 })
    #expect(first.first?.evidenceText == context.recentTranscript)
}

@Test func mockGeneratorRespectsCancellationDuringDelay() async {
    let generator = MockCommentGenerator(
        delayMilliseconds: 2_000,
        comments: [MockGeneratedComment(judgeID: .audience, text: "遅い候補", emotion: .curious, priority: 60)]
    )
    let context = CommentGenerationContext(
        requestedAtMs: 0,
        recentTranscript: "テスト",
        session: SessionDescriptor(title: "", goal: "", audience: "", plannedDurationSeconds: 60),
        remainingSeconds: 60
    )

    let task = Task { try await generator.generateComments(for: context) }
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("キャンセルされた生成が成功してしまった")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("想定外のエラー: \(error)")
    }
}
