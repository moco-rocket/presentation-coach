import Foundation

public protocol ReportEvaluating: Sendable {
    func evaluate(_ report: SessionReport) async throws -> QualitativeEvaluation
}

public enum OpenAIReportEvaluatorError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case insufficientEvidence
    case invalidResponse
    case httpStatus(Int)
    case emptyEvaluation

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "OPENAI_API_KEY が設定されていません。"
        case .insufficientEvidence: "講評に使える発表記録がありません。"
        case .invalidResponse: "OpenAI APIから不正な講評応答を受信しました。"
        case let .httpStatus(status): "OpenAI APIがHTTP \(status)を返しました。"
        case .emptyEvaluation: "OpenAI APIの講評が空でした。"
        }
    }
}

public struct OpenAIReportEvaluator: ReportEvaluating, Sendable {
    private let apiKey: String
    private let model: String
    private let endpoint: URL
    private let loader: any HTTPDataLoading

    public init(
        apiKey: String,
        model: String = "gpt-5-mini",
        endpoint: URL = OpenAICommentGenerator.defaultEndpoint,
        loader: any HTTPDataLoading = URLSessionHTTPDataLoader()
    ) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw OpenAIReportEvaluatorError.missingAPIKey }
        self.apiKey = trimmedKey
        self.model = model
        self.endpoint = endpoint
        self.loader = loader
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        loader: any HTTPDataLoading = URLSessionHTTPDataLoader()
    ) throws -> OpenAIReportEvaluator {
        guard let apiKey = environment["OPENAI_API_KEY"] else {
            throw OpenAIReportEvaluatorError.missingAPIKey
        }
        return try OpenAIReportEvaluator(
            apiKey: apiKey,
            model: environment["OPENAI_MODEL"] ?? "gpt-5-mini",
            loader: loader
        )
    }

    public static func configured(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: any OpenAICredentialStoring = KeychainOpenAICredentialStore(),
        loader: any HTTPDataLoading = URLSessionHTTPDataLoader()
    ) throws -> OpenAIReportEvaluator {
        guard let apiKey = try OpenAICredentialResolver.resolve(environment: environment, store: store) else {
            throw OpenAIReportEvaluatorError.missingAPIKey
        }
        return try OpenAIReportEvaluator(
            apiKey: apiKey,
            model: environment["OPENAI_MODEL"] ?? "gpt-5-mini",
            loader: loader
        )
    }

    public func evaluate(_ report: SessionReport) async throws -> QualitativeEvaluation {
        guard !report.evidence.isEmpty else { throw OpenAIReportEvaluatorError.insufficientEvidence }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.makeRequestBody(model: model, report: report)

        let (data, response) = try await loader.data(for: request)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIReportEvaluatorError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAIReportEvaluatorError.httpStatus(httpResponse.statusCode)
        }
        let envelope = try JSONDecoder().decode(EvaluationResponseEnvelope.self, from: data)
        guard let outputText = envelope.output.flatMap(\.content).compactMap(\.text).first,
              let outputData = outputText.data(using: .utf8) else {
            throw OpenAIReportEvaluatorError.invalidResponse
        }
        let generated = try JSONDecoder().decode(GeneratedEvaluation.self, from: outputData)
        let evaluation = QualitativeEvaluation(
            strengths: Self.map(generated.strengths, to: report.evidence),
            improvements: Self.map(generated.improvements, to: report.evidence),
            nextActions: Self.map(generated.nextActions, to: report.evidence)
        )
        guard !evaluation.strengths.isEmpty || !evaluation.improvements.isEmpty || !evaluation.nextActions.isEmpty else {
            throw OpenAIReportEvaluatorError.emptyEvaluation
        }
        return evaluation
    }

    private static func map(
        _ generated: [GeneratedEvaluation.Insight],
        to evidence: [SessionEvidence]
    ) -> [EvaluatedInsight] {
        generated.prefix(3).compactMap { insight in
            guard evidence.indices.contains(insight.evidenceIndex) else { return nil }
            return EvaluatedInsight(text: insight.text, evidence: evidence[insight.evidenceIndex])
        }
    }

    private static func makeRequestBody(model: String, report: SessionReport) throws -> Data {
        let scoreLines = report.score.categories.map {
            "\($0.category): \($0.score)/\($0.maximumScore)（\($0.evidence.joined(separator: "、"))）"
        }.joined(separator: "\n")
        let evidenceLines = report.evidence.enumerated().map { index, evidence in
            "[\(index)] \(format(milliseconds: evidence.timestampMs)) \(evidence.kind.rawValue): \(String(evidence.text.prefix(300)))"
        }.joined(separator: "\n")
        let prompt = """
        発表練習の終了後コーチです。計測スコアを変更せず、良かった点、改善点、次回の具体的課題を日本語で各1〜3件作ってください。
        必ず下の根拠番号を1つ選び、観測事実を越えて断定しないでください。短く、率直で、実行可能な講評にしてください。

        発表: \(report.session.title)
        目的: \(report.session.goal)
        聴衆: \(report.session.audience)
        スコア: \(report.score.totalScore)/\(report.score.maximumScore)
        \(scoreLines)

        根拠:
        \(evidenceLines)
        """
        let body: [String: Any] = [
            "model": model,
            "input": prompt,
            "max_output_tokens": 900,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "presentation_evaluation",
                    "strict": true,
                    "schema": responseSchema(maximumEvidenceIndex: report.evidence.count - 1)
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private static func responseSchema(maximumEvidenceIndex: Int) -> [String: Any] {
        let insight: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["text", "evidenceIndex"],
            "properties": [
                "text": ["type": "string"],
                "evidenceIndex": [
                    "type": "integer",
                    "minimum": 0,
                    "maximum": maximumEvidenceIndex
                ]
            ]
        ]
        let list: [String: Any] = ["type": "array", "minItems": 1, "maxItems": 3, "items": insight]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["strengths", "improvements", "nextActions"],
            "properties": ["strengths": list, "improvements": list, "nextActions": list]
        ]
    }

    private static func format(milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds / 1_000)
        return String(format: "%02lld:%02lld", seconds / 60, seconds % 60)
    }
}

private struct EvaluationResponseEnvelope: Decodable {
    struct Output: Decodable {
        struct Content: Decodable { var text: String? }
        var content: [Content]
    }
    var output: [Output]
}

private struct GeneratedEvaluation: Decodable {
    struct Insight: Decodable {
        var text: String
        var evidenceIndex: Int
    }
    var strengths: [Insight]
    var improvements: [Insight]
    var nextActions: [Insight]
}
