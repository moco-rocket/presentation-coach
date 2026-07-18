import Foundation
import PresentationContracts

public enum OpenAICommentGeneratorError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int)
    case emptyOutput

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "OPENAI_API_KEY が設定されていません。"
        case .invalidResponse: "OpenAI APIから不正な応答を受信しました。"
        case let .httpStatus(status): "OpenAI APIがHTTP \(status)を返しました。"
        case .emptyOutput: "OpenAI APIの応答にコメントがありません。"
        }
    }
}

public protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionHTTPDataLoader: HTTPDataLoading, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// Low-latency Responses API adapter. The API key is held only in memory and is
/// never written to a session recording.
public struct OpenAICommentGenerator: CommentGenerating, Sendable {
    public static let defaultEndpoint = URL(string: "https://api.openai.com/v1/responses")!

    private let apiKey: String
    private let model: String
    private let endpoint: URL
    private let timeoutSeconds: TimeInterval
    private let loader: any HTTPDataLoading

    public init(
        apiKey: String,
        model: String = "gpt-5-mini",
        endpoint: URL = defaultEndpoint,
        timeoutSeconds: TimeInterval = 2.5,
        loader: any HTTPDataLoading = URLSessionHTTPDataLoader()
    ) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw OpenAICommentGeneratorError.missingAPIKey }
        self.apiKey = trimmedKey
        self.model = model
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
        self.loader = loader
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        loader: any HTTPDataLoading = URLSessionHTTPDataLoader()
    ) throws -> OpenAICommentGenerator {
        guard let apiKey = environment["OPENAI_API_KEY"] else {
            throw OpenAICommentGeneratorError.missingAPIKey
        }
        return try OpenAICommentGenerator(
            apiKey: apiKey,
            model: environment["OPENAI_MODEL"] ?? "gpt-5-mini",
            loader: loader
        )
    }

    public static func configured(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: any OpenAICredentialStoring = KeychainOpenAICredentialStore(),
        loader: any HTTPDataLoading = URLSessionHTTPDataLoader()
    ) throws -> OpenAICommentGenerator {
        guard let apiKey = try OpenAICredentialResolver.resolve(environment: environment, store: store) else {
            throw OpenAICommentGeneratorError.missingAPIKey
        }
        return try OpenAICommentGenerator(
            apiKey: apiKey,
            model: environment["OPENAI_MODEL"] ?? "gpt-5-mini",
            loader: loader
        )
    }

    public func generateComments(for context: CommentGenerationContext) async throws -> [CommentCandidate] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.makeRequestBody(model: model, context: context)

        let (data, response) = try await loader.data(for: request)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAICommentGeneratorError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAICommentGeneratorError.httpStatus(httpResponse.statusCode)
        }

        let responseEnvelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        let outputText = responseEnvelope.output
            .flatMap(\.content)
            .compactMap(\.text)
            .first
        guard let outputText, let outputData = outputText.data(using: .utf8) else {
            throw OpenAICommentGeneratorError.emptyOutput
        }
        let generated = try JSONDecoder().decode(GeneratedEnvelope.self, from: outputData)

        return generated.comments.prefix(3).map { comment in
            CommentCandidate(
                judgeID: comment.judgeID,
                text: String(comment.text.prefix(80)),
                emotion: comment.emotion,
                priority: min(100, max(0, comment.priority)),
                confidence: min(1, max(0, comment.confidence)),
                evidenceText: comment.evidenceText,
                source: .llm,
                createdAtMs: context.requestedAtMs,
                expiresAtMs: context.requestedAtMs + 3_000
            )
        }
    }

    private static func makeRequestBody(model: String, context: CommentGenerationContext) throws -> Data {
        let prompt = """
        あなたは発表練習を見守る4人の審査員です。今この瞬間に役立ち、短く、コミカルだが失礼ではない日本語コメントを0〜3件返してください。
        発表: \(context.session.title)
        目的: \(context.session.goal)
        聴衆: \(context.session.audience)
        残り時間: \(context.remainingSeconds)秒
        現在の区切り: \(context.currentSection ?? "不明")
        最近の発話: \(context.recentTranscript)
        現在のスライド: \(context.currentSlideOCR ?? "不明")
        直近に表示済み: \(context.recentDisplayedComments.joined(separator: " / "))

        同じ指摘の繰り返しを避け、観測できた根拠を evidenceText に短く入れてください。
        """
        let body: [String: Any] = [
            "model": model,
            "input": prompt,
            "max_output_tokens": 500,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "presentation_comments",
                    "strict": true,
                    "schema": responseSchema
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private static var responseSchema: [String: Any] { [
        "type": "object",
        "additionalProperties": false,
        "required": ["comments"],
        "properties": [
            "comments": [
                "type": "array",
                "maxItems": 3,
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["judgeID", "text", "emotion", "priority", "confidence", "evidenceText"],
                    "properties": [
                        "judgeID": ["type": "string", "enum": JudgeID.allCases.map(\.rawValue)],
                        "text": ["type": "string"],
                        "emotion": ["type": "string", "enum": ReactionEmotion.allCases.map(\.rawValue)],
                        "priority": ["type": "integer", "minimum": 0, "maximum": 100],
                        "confidence": ["type": "number", "minimum": 0, "maximum": 1],
                        "evidenceText": ["type": "string"]
                    ]
                ]
            ]
        ]
    ] }
}

private struct ResponseEnvelope: Decodable {
    struct Output: Decodable {
        struct Content: Decodable {
            var text: String?
        }
        var content: [Content]
    }
    var output: [Output]
}

private struct GeneratedEnvelope: Decodable {
    struct Comment: Decodable {
        var judgeID: JudgeID
        var text: String
        var emotion: ReactionEmotion
        var priority: Int
        var confidence: Double
        var evidenceText: String
    }
    var comments: [Comment]
}
