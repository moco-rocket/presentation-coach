import Foundation
import PresentationContracts
import Testing
@testable import PresentationFeedback

private struct StubLoader: HTTPDataLoading {
    var handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}

@Test func openAIGeneratorBuildsStructuredRequestAndMapsComments() async throws {
    let responseJSON = #"{"output":[{"content":[{"type":"output_text","text":"{\"comments\":[{\"judgeID\":\"clarity\",\"text\":\"結論が見えた！\",\"emotion\":\"happy\",\"priority\":72,\"confidence\":0.91,\"evidenceText\":\"結論から話します\"}]}"}]}]}"#
    let loader = StubLoader { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "gpt-5-mini")
        let text = try #require(object["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        return (
            Data(responseJSON.utf8),
            HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
    let generator = try OpenAICommentGenerator(apiKey: "test-token", loader: loader)
    let context = CommentGenerationContext(
        requestedAtMs: 1_000,
        recentTranscript: "結論から話します",
        currentSlideOCR: "まとめ",
        session: SessionDescriptor(
            title: "発表",
            goal: "練習",
            audience: "審査員",
            plannedDurationSeconds: 60
        ),
        remainingSeconds: 20
    )

    let comments = try await generator.generateComments(for: context)

    #expect(comments.count == 1)
    #expect(comments[0].judgeID == .clarity)
    #expect(comments[0].text == "結論が見えた！")
    #expect(comments[0].source == .llm)
    #expect(comments[0].createdAtMs == 1_000)
    #expect(comments[0].expiresAtMs == 4_000)
}

@Test func openAIGeneratorRequiresEnvironmentCredential() throws {
    #expect(throws: OpenAICommentGeneratorError.missingAPIKey) {
        try OpenAICommentGenerator.fromEnvironment([:])
    }
    let generator = try OpenAICommentGenerator.fromEnvironment([
        "OPENAI_API_KEY": "configured",
        "OPENAI_MODEL": "custom-model"
    ])
    _ = generator
}

@Test func openAIGeneratorRejectsHTTPFailureWithoutExposingBody() async throws {
    let loader = StubLoader { request in
        (
            Data("secret response".utf8),
            HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
    let generator = try OpenAICommentGenerator(apiKey: "test-token", loader: loader)
    let context = CommentGenerationContext(
        requestedAtMs: 0,
        recentTranscript: "",
        session: SessionDescriptor(title: "", goal: "", audience: "", plannedDurationSeconds: 0),
        remainingSeconds: 0
    )

    await #expect(throws: OpenAICommentGeneratorError.httpStatus(429)) {
        try await generator.generateComments(for: context)
    }
}
