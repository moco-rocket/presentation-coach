import Foundation

public enum JudgeID: String, Codable, CaseIterable, Sendable {
    case tempo
    case clarity
    case slide
    case audience
}

public enum ReactionEmotion: String, Codable, CaseIterable, Sendable {
    case idle
    case happy
    case curious
    case confused
    case panic
    case sleepy
    case impressed
}

public enum CommentSource: String, Codable, Sendable {
    case rule
    case llm
}

public struct SessionDescriptor: Codable, Equatable, Sendable {
    public var title: String
    public var goal: String
    public var audience: String
    public var plannedDurationSeconds: Int

    public init(
        title: String,
        goal: String,
        audience: String,
        plannedDurationSeconds: Int
    ) {
        self.title = title
        self.goal = goal
        self.audience = audience
        self.plannedDurationSeconds = plannedDurationSeconds
    }
}

public struct AudioMetric: Codable, Equatable, Sendable {
    public var rmsDB: Double
    public var peakDB: Double
    public var isSpeech: Bool
    public var silenceDurationMs: Int

    public init(rmsDB: Double, peakDB: Double, isSpeech: Bool, silenceDurationMs: Int) {
        self.rmsDB = rmsDB
        self.peakDB = peakDB
        self.isSpeech = isSpeech
        self.silenceDurationMs = silenceDurationMs
    }
}

public struct SpeechSegment: Codable, Equatable, Sendable {
    public var text: String
    public var startedAtMs: Int64
    public var endedAtMs: Int64?
    public var confidence: Double?

    public init(
        text: String,
        startedAtMs: Int64,
        endedAtMs: Int64? = nil,
        confidence: Double? = nil
    ) {
        self.text = text
        self.startedAtMs = startedAtMs
        self.endedAtMs = endedAtMs
        self.confidence = confidence
    }
}

public struct SlideChange: Codable, Equatable, Sendable {
    public var slideID: String
    public var ocrText: String?
    public var textDensity: Double?

    public init(slideID: String, ocrText: String? = nil, textDensity: Double? = nil) {
        self.slideID = slideID
        self.ocrText = ocrText
        self.textDensity = textDensity
    }
}

public struct CommentCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var judgeID: JudgeID
    public var text: String
    public var emotion: ReactionEmotion
    public var priority: Int
    public var confidence: Double
    public var evidenceText: String?
    public var source: CommentSource
    public var createdAtMs: Int64
    public var expiresAtMs: Int64

    public init(
        id: UUID = UUID(),
        judgeID: JudgeID,
        text: String,
        emotion: ReactionEmotion,
        priority: Int,
        confidence: Double,
        evidenceText: String? = nil,
        source: CommentSource,
        createdAtMs: Int64,
        expiresAtMs: Int64
    ) {
        self.id = id
        self.judgeID = judgeID
        self.text = text
        self.emotion = emotion
        self.priority = priority
        self.confidence = confidence
        self.evidenceText = evidenceText
        self.source = source
        self.createdAtMs = createdAtMs
        self.expiresAtMs = expiresAtMs
    }
}

public struct JudgeReaction: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var candidateID: UUID
    public var judgeID: JudgeID
    public var text: String
    public var emotion: ReactionEmotion
    public var source: CommentSource
    public var durationMs: Int

    public init(
        id: UUID = UUID(),
        candidateID: UUID,
        judgeID: JudgeID,
        text: String,
        emotion: ReactionEmotion,
        source: CommentSource,
        durationMs: Int
    ) {
        self.id = id
        self.candidateID = candidateID
        self.judgeID = judgeID
        self.text = text
        self.emotion = emotion
        self.source = source
        self.durationMs = durationMs
    }
}

public struct TimerUpdate: Codable, Equatable, Sendable {
    public var elapsedSeconds: Int
    public var remainingSeconds: Int

    public init(elapsedSeconds: Int, remainingSeconds: Int) {
        self.elapsedSeconds = elapsedSeconds
        self.remainingSeconds = remainingSeconds
    }
}

public struct ScoreUpdate: Codable, Equatable, Sendable {
    public var category: String
    public var score: Double
    public var maximumScore: Double
    public var evidence: [String]

    public init(category: String, score: Double, maximumScore: Double, evidence: [String]) {
        self.category = category
        self.score = score
        self.maximumScore = maximumScore
        self.evidence = evidence
    }
}

public enum PresentationEventKind: String, Codable, Sendable {
    case sessionStarted
    case sessionStopped
    case audioMetric
    case speechPartial
    case speechFinal
    case slideChanged
    case ruleCommentCandidate
    case llmCommentCandidate
    case judgeReaction
    case timerUpdated
    case scoreUpdated
}

public enum PresentationEventPayload: Codable, Equatable, Sendable {
    case session(SessionDescriptor)
    case audioMetric(AudioMetric)
    case speech(SpeechSegment)
    case slideChange(SlideChange)
    case commentCandidate(CommentCandidate)
    case judgeReaction(JudgeReaction)
    case timer(TimerUpdate)
    case score(ScoreUpdate)
    case none
}

public struct PresentationEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var timestampMs: Int64
    public var kind: PresentationEventKind
    public var payload: PresentationEventPayload

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestampMs: Int64,
        kind: PresentationEventKind,
        payload: PresentationEventPayload
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestampMs = timestampMs
        self.kind = kind
        self.payload = payload
    }
}
