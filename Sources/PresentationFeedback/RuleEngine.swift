import Foundation
import PresentationContracts

/// Low-latency, deterministic feedback derived without a network or model call.
public struct RuleEngine: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var longSilenceMilliseconds: Int
        public var quietSpeechDB: Double
        public var clippingPeakDB: Double
        public var fastSpeechCharactersPerSecond: Double
        public var repeatedFillerCount: Int
        public var denseSlideThreshold: Double
        public var candidateLifetimeMilliseconds: Int64

        public init(
            longSilenceMilliseconds: Int = 2_500,
            quietSpeechDB: Double = -36,
            clippingPeakDB: Double = -1,
            fastSpeechCharactersPerSecond: Double = 7,
            repeatedFillerCount: Int = 2,
            denseSlideThreshold: Double = 0.72,
            candidateLifetimeMilliseconds: Int64 = 3_000
        ) {
            self.longSilenceMilliseconds = longSilenceMilliseconds
            self.quietSpeechDB = quietSpeechDB
            self.clippingPeakDB = clippingPeakDB
            self.fastSpeechCharactersPerSecond = fastSpeechCharactersPerSecond
            self.repeatedFillerCount = repeatedFillerCount
            self.denseSlideThreshold = denseSlideThreshold
            self.candidateLifetimeMilliseconds = candidateLifetimeMilliseconds
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// The same event and configuration always produce equivalent candidates,
    /// including stable candidate identifiers.
    public func candidates(for event: PresentationEvent) -> [CommentCandidate] {
        let drafts: [Draft]

        switch (event.kind, event.payload) {
        case (.audioMetric, .audioMetric(let metric)):
            drafts = audioDrafts(metric)
        case (.speechFinal, .speech(let segment)):
            drafts = speechDrafts(segment)
        case (.slideChanged, .slideChange(let slide)):
            drafts = slideDrafts(slide)
        default:
            drafts = []
        }

        return drafts.enumerated().map { index, draft in
            CommentCandidate(
                id: Self.stableID(eventID: event.id, ruleID: draft.ruleID, index: index),
                judgeID: draft.judgeID,
                text: draft.text,
                emotion: draft.emotion,
                priority: draft.priority,
                confidence: draft.confidence,
                evidenceText: draft.evidence,
                source: .rule,
                createdAtMs: event.timestampMs,
                expiresAtMs: event.timestampMs + configuration.candidateLifetimeMilliseconds
            )
        }
        .sorted(by: Self.precedes)
    }

    private func audioDrafts(_ metric: AudioMetric) -> [Draft] {
        var result: [Draft] = []

        if !metric.isSpeech, metric.silenceDurationMs >= configuration.longSilenceMilliseconds {
            result.append(Draft(
                ruleID: "long-silence",
                judgeID: .tempo,
                text: "間が長くなってきたよ",
                emotion: .curious,
                priority: 86,
                confidence: 0.98,
                evidence: "無音 \(metric.silenceDurationMs)ms"
            ))
        }

        if metric.isSpeech, metric.peakDB >= configuration.clippingPeakDB {
            result.append(Draft(
                ruleID: "clipping",
                judgeID: .clarity,
                text: "音が割れそう！少し抑えて",
                emotion: .panic,
                priority: 94,
                confidence: 0.96,
                evidence: String(format: "ピーク %.1fdB", metric.peakDB)
            ))
        } else if metric.isSpeech, metric.rmsDB <= configuration.quietSpeechDB {
            result.append(Draft(
                ruleID: "quiet-speech",
                judgeID: .clarity,
                text: "もう少し声を届けて！",
                emotion: .curious,
                priority: 76,
                confidence: 0.9,
                evidence: String(format: "平均音量 %.1fdB", metric.rmsDB)
            ))
        }

        return result
    }

    private func speechDrafts(_ segment: SpeechSegment) -> [Draft] {
        var result: [Draft] = []
        let fillerCount = Self.fillerCount(in: segment.text)

        if fillerCount >= configuration.repeatedFillerCount {
            result.append(Draft(
                ruleID: "repeated-fillers",
                judgeID: .clarity,
                text: "えーとが続いたぞ",
                emotion: .confused,
                priority: 79,
                confidence: 0.92,
                evidence: "フィラー \(fillerCount)回"
            ))
        }

        if let endedAtMs = segment.endedAtMs, endedAtMs > segment.startedAtMs {
            let seconds = Double(endedAtMs - segment.startedAtMs) / 1_000
            let characterCount = segment.text.unicodeScalars.filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
            }.count
            let rate = Double(characterCount) / seconds

            if rate >= configuration.fastSpeechCharactersPerSecond {
                result.append(Draft(
                    ruleID: "fast-speech",
                    judgeID: .tempo,
                    text: "ちょっと速い速い！",
                    emotion: .panic,
                    priority: 84,
                    confidence: 0.9,
                    evidence: String(format: "話速 %.1f文字/秒", rate)
                ))
            }
        }

        return result
    }

    private func slideDrafts(_ slide: SlideChange) -> [Draft] {
        guard let density = slide.textDensity, density >= configuration.denseSlideThreshold else {
            return []
        }

        return [Draft(
            ruleID: "dense-slide",
            judgeID: .slide,
            text: "文字がぎゅうぎゅうだ！",
            emotion: .panic,
            priority: 82,
            confidence: 0.94,
            evidence: String(format: "文字密度 %.0f%%", density * 100)
        )]
    }

    private static func fillerCount(in text: String) -> Int {
        var remainder = text.lowercased()
        var count = 0
        // Longest first avoids counting `あのー` twice as `あのー` and `あの`.
        for filler in ["えーっと", "ええと", "えーと", "えっと", "あのー", "そのー", "あの"] {
            let occurrences = remainder.components(separatedBy: filler).count - 1
            count += occurrences
            remainder = remainder.replacingOccurrences(of: filler, with: " ")
        }
        return count
    }

    private static func precedes(_ lhs: CommentCandidate, _ rhs: CommentCandidate) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func stableID(eventID: UUID, ruleID: String, index: Int) -> UUID {
        let input = "\(eventID.uuidString)|\(ruleID)|\(index)"
        let high = fnv1a64(input.utf8, seed: 14_695_981_039_346_656_037)
        let low = fnv1a64(input.utf8, seed: 10_995_116_282_11)
        let hex = String(format: "%016llx%016llx", high, low)
        let characters = Array(hex)
        let formatted = [8, 4, 4, 4, 12].reduce(into: (parts: [String](), offset: 0)) { state, length in
            state.parts.append(String(characters[state.offset..<(state.offset + length)]))
            state.offset += length
        }.parts.joined(separator: "-")
        return UUID(uuidString: formatted)!
    }

    private static func fnv1a64<S: Sequence>(_ bytes: S, seed: UInt64) -> UInt64 where S.Element == UInt8 {
        bytes.reduce(seed) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

private extension RuleEngine {
    struct Draft {
        let ruleID: String
        let judgeID: JudgeID
        let text: String
        let emotion: ReactionEmotion
        let priority: Int
        let confidence: Double
        let evidence: String
    }
}
