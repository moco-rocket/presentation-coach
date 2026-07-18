import Foundation
import PresentationContracts

public struct SlidePacingTracker: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var longDwellMilliseconds: Int64
        public var rapidChangeWindowMilliseconds: Int64
        public var rapidChangeCount: Int
        public var candidateLifetimeMilliseconds: Int64

        public init(
            longDwellMilliseconds: Int64 = 90_000,
            rapidChangeWindowMilliseconds: Int64 = 15_000,
            rapidChangeCount: Int = 4,
            candidateLifetimeMilliseconds: Int64 = 3_000
        ) {
            self.longDwellMilliseconds = max(1, longDwellMilliseconds)
            self.rapidChangeWindowMilliseconds = max(1, rapidChangeWindowMilliseconds)
            self.rapidChangeCount = max(2, rapidChangeCount)
            self.candidateLifetimeMilliseconds = max(1, candidateLifetimeMilliseconds)
        }
    }

    public let configuration: Configuration
    private var currentSlideID: String?
    private var currentSlideStartedAtMs: Int64?
    private var recentChangeTimestamps: [Int64] = []
    private var warnedForCurrentDwell = false
    private var lastRapidWarningAtMs: Int64?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public mutating func candidates(for event: PresentationEvent) -> [CommentCandidate] {
        switch (event.kind, event.payload) {
        case let (.slideChanged, .slideChange(slide)):
            return handleSlideChange(slide, event: event)
        case (.timerUpdated, .timer):
            return handleTimer(event)
        default:
            return []
        }
    }

    public mutating func reset() {
        currentSlideID = nil
        currentSlideStartedAtMs = nil
        recentChangeTimestamps.removeAll()
        warnedForCurrentDwell = false
        lastRapidWarningAtMs = nil
    }

    private mutating func handleSlideChange(
        _ slide: SlideChange,
        event: PresentationEvent
    ) -> [CommentCandidate] {
        guard slide.slideID != currentSlideID else { return [] }
        var candidates: [CommentCandidate] = []
        if let startedAt = currentSlideStartedAtMs,
           !warnedForCurrentDwell,
           event.timestampMs - startedAt >= configuration.longDwellMilliseconds {
            candidates.append(makeCandidate(
                event: event,
                ruleID: "long-slide-dwell",
                text: "この1枚、ちょっと長かったかも",
                emotion: .sleepy,
                priority: 70,
                evidence: "スライド滞在 \((event.timestampMs - startedAt) / 1_000)秒"
            ))
        }

        currentSlideID = slide.slideID
        currentSlideStartedAtMs = event.timestampMs
        warnedForCurrentDwell = false
        recentChangeTimestamps.append(event.timestampMs)
        recentChangeTimestamps.removeAll {
            event.timestampMs - $0 > configuration.rapidChangeWindowMilliseconds
        }
        let rapidWarningIsCoolingDown = lastRapidWarningAtMs.map {
            event.timestampMs - $0 < configuration.rapidChangeWindowMilliseconds
        } ?? false
        if recentChangeTimestamps.count >= configuration.rapidChangeCount && !rapidWarningIsCoolingDown {
            lastRapidWarningAtMs = event.timestampMs
            candidates.append(makeCandidate(
                event: event,
                ruleID: "rapid-slide-changes",
                text: "スライドが目まぐるしいぞ！",
                emotion: .panic,
                priority: 78,
                evidence: "\(configuration.rapidChangeWindowMilliseconds / 1_000)秒で\(recentChangeTimestamps.count)枚"
            ))
        }
        return candidates
    }

    private mutating func handleTimer(_ event: PresentationEvent) -> [CommentCandidate] {
        guard let startedAt = currentSlideStartedAtMs,
              !warnedForCurrentDwell,
              event.timestampMs - startedAt >= configuration.longDwellMilliseconds else { return [] }
        warnedForCurrentDwell = true
        return [makeCandidate(
            event: event,
            ruleID: "long-slide-dwell",
            text: "そろそろ次の展開が見たいな",
            emotion: .sleepy,
            priority: 70,
            evidence: "スライド滞在 \((event.timestampMs - startedAt) / 1_000)秒"
        )]
    }

    private func makeCandidate(
        event: PresentationEvent,
        ruleID: String,
        text: String,
        emotion: ReactionEmotion,
        priority: Int,
        evidence: String
    ) -> CommentCandidate {
        CommentCandidate(
            id: stableID(eventID: event.id, ruleID: ruleID),
            judgeID: .slide,
            text: text,
            emotion: emotion,
            priority: priority,
            confidence: 0.95,
            evidenceText: evidence,
            source: .rule,
            createdAtMs: event.timestampMs,
            expiresAtMs: event.timestampMs + configuration.candidateLifetimeMilliseconds
        )
    }

    private func stableID(eventID: UUID, ruleID: String) -> UUID {
        let bytes = Array("\(eventID.uuidString)|\(ruleID)".utf8)
        var values = [UInt8](repeating: 0, count: 16)
        for (index, byte) in bytes.enumerated() {
            values[index % 16] = values[index % 16] &+ byte &+ UInt8(truncatingIfNeeded: index)
        }
        return UUID(uuid: (
            values[0], values[1], values[2], values[3],
            values[4], values[5], values[6], values[7],
            values[8], values[9], values[10], values[11],
            values[12], values[13], values[14], values[15]
        ))
    }
}
