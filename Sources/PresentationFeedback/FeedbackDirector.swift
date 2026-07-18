import Foundation
import PresentationContracts

/// Serializes competing rule/LLM candidates into at most one UI reaction.
public actor FeedbackDirector {
    public struct Configuration: Equatable, Sendable {
        public var judgeCooldownMilliseconds: Int64
        public var duplicateWindowMilliseconds: Int64
        public var maximumCommentCharacters: Int
        public var minimumDurationMilliseconds: Int
        public var maximumDurationMilliseconds: Int

        public init(
            judgeCooldownMilliseconds: Int64 = 6_000,
            duplicateWindowMilliseconds: Int64 = 30_000,
            maximumCommentCharacters: Int = 40,
            minimumDurationMilliseconds: Int = 1_800,
            maximumDurationMilliseconds: Int = 3_500
        ) {
            self.judgeCooldownMilliseconds = judgeCooldownMilliseconds
            self.duplicateWindowMilliseconds = duplicateWindowMilliseconds
            self.maximumCommentCharacters = maximumCommentCharacters
            self.minimumDurationMilliseconds = minimumDurationMilliseconds
            self.maximumDurationMilliseconds = maximumDurationMilliseconds
        }
    }

    private struct DisplayRecord: Sendable {
        let normalizedText: String
        let displayedAtMs: Int64
    }

    public let configuration: Configuration
    private var lastDisplayedByJudge: [JudgeID: Int64] = [:]
    private var recentDisplays: [DisplayRecord] = []

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public func select(from candidates: [CommentCandidate], at nowMs: Int64) -> JudgeReaction? {
        recentDisplays.removeAll { nowMs - $0.displayedAtMs >= configuration.duplicateWindowMilliseconds }

        let eligible = candidates.filter { candidate in
            guard candidate.createdAtMs <= nowMs, candidate.expiresAtMs > nowMs else { return false }

            if let lastShown = lastDisplayedByJudge[candidate.judgeID],
               nowMs - lastShown < configuration.judgeCooldownMilliseconds {
                return false
            }

            let normalized = Self.normalize(candidate.text)
            return !normalized.isEmpty && !recentDisplays.contains { $0.normalizedText == normalized }
        }

        guard let winner = eligible.sorted(by: Self.precedes).first else { return nil }
        let text = Self.truncate(winner.text, to: configuration.maximumCommentCharacters)
        let duration = min(
            configuration.maximumDurationMilliseconds,
            max(configuration.minimumDurationMilliseconds, 1_200 + text.count * 70)
        )

        lastDisplayedByJudge[winner.judgeID] = nowMs
        recentDisplays.append(DisplayRecord(normalizedText: Self.normalize(winner.text), displayedAtMs: nowMs))

        return JudgeReaction(
            candidateID: winner.id,
            judgeID: winner.judgeID,
            text: text,
            emotion: winner.emotion,
            source: winner.source,
            durationMs: duration
        )
    }

    public func reset() {
        lastDisplayedByJudge.removeAll()
        recentDisplays.removeAll()
    }

    private static func precedes(_ lhs: CommentCandidate, _ rhs: CommentCandidate) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.source != rhs.source { return lhs.source == .llm }
        if lhs.createdAtMs != rhs.createdAtMs { return lhs.createdAtMs > rhs.createdAtMs }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func normalize(_ text: String) -> String {
        let ignored = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
        return String(text.lowercased().unicodeScalars.filter { !ignored.contains($0) })
    }

    private static func truncate(_ text: String, to maximum: Int) -> String {
        guard maximum > 0, text.count > maximum else { return text }
        if maximum == 1 { return "…" }
        return String(text.prefix(maximum - 1)) + "…"
    }
}
