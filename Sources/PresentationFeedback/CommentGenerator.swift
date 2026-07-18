import Foundation
import PresentationContracts

public struct CommentGenerationContext: Equatable, Sendable {
    public var requestedAtMs: Int64
    public var recentTranscript: String
    public var currentSlideOCR: String?
    public var session: SessionDescriptor
    public var currentSection: String?
    public var remainingSeconds: Int
    public var recentDisplayedComments: [String]

    public init(
        requestedAtMs: Int64,
        recentTranscript: String,
        currentSlideOCR: String? = nil,
        session: SessionDescriptor,
        currentSection: String? = nil,
        remainingSeconds: Int,
        recentDisplayedComments: [String] = []
    ) {
        self.requestedAtMs = requestedAtMs
        self.recentTranscript = recentTranscript
        self.currentSlideOCR = currentSlideOCR
        self.session = session
        self.currentSection = currentSection
        self.remainingSeconds = remainingSeconds
        self.recentDisplayedComments = recentDisplayedComments
    }
}

public protocol CommentGenerating: Sendable {
    func generateComments(for context: CommentGenerationContext) async throws -> [CommentCandidate]
}

public struct MockGeneratedComment: Equatable, Sendable {
    public var judgeID: JudgeID
    public var text: String
    public var emotion: ReactionEmotion
    public var priority: Int
    public var confidence: Double
    public var evidenceText: String?
    public var lifetimeMilliseconds: Int64

    public init(
        judgeID: JudgeID,
        text: String,
        emotion: ReactionEmotion,
        priority: Int,
        confidence: Double = 0.9,
        evidenceText: String? = nil,
        lifetimeMilliseconds: Int64 = 3_000
    ) {
        self.judgeID = judgeID
        self.text = text
        self.emotion = emotion
        self.priority = priority
        self.confidence = confidence
        self.evidenceText = evidenceText
        self.lifetimeMilliseconds = lifetimeMilliseconds
    }
}

/// A cancellable stand-in for the future HTTP LLM adapter.
public struct MockCommentGenerator: CommentGenerating, Sendable {
    public var delayMilliseconds: Int
    public var comments: [MockGeneratedComment]

    public init(delayMilliseconds: Int = 75, comments: [MockGeneratedComment]) {
        self.delayMilliseconds = max(0, delayMilliseconds)
        self.comments = comments
    }

    public func generateComments(for context: CommentGenerationContext) async throws -> [CommentCandidate] {
        if delayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(delayMilliseconds))
        }
        try Task.checkCancellation()

        return comments.prefix(3).enumerated().map { index, comment in
            CommentCandidate(
                id: Self.stableID(context: context, index: index),
                judgeID: comment.judgeID,
                text: comment.text,
                emotion: comment.emotion,
                priority: comment.priority,
                confidence: comment.confidence,
                evidenceText: comment.evidenceText ?? context.recentTranscript,
                source: .llm,
                createdAtMs: context.requestedAtMs,
                expiresAtMs: context.requestedAtMs + comment.lifetimeMilliseconds
            )
        }
    }

    private static func stableID(context: CommentGenerationContext, index: Int) -> UUID {
        var bytes = Array("\(context.requestedAtMs)|\(context.recentTranscript)|\(index)".utf8)
        bytes.append(contentsOf: context.session.title.utf8)
        var high: UInt64 = 14_695_981_039_346_656_037
        var low: UInt64 = 1_099_511_628_211
        for byte in bytes {
            high = (high ^ UInt64(byte)) &* 1_099_511_628_211
            low = (low ^ UInt64(byte)) &* 14_029_467_366_897_019_727
        }
        let hex = String(format: "%016llx%016llx", high, low)
        let c = Array(hex)
        let string = "\(String(c[0..<8]))-\(String(c[8..<12]))-\(String(c[12..<16]))-\(String(c[16..<20]))-\(String(c[20..<32]))"
        return UUID(uuidString: string)!
    }
}
