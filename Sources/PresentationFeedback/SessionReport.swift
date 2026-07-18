import Foundation
import PresentationContracts

public struct SessionReport: Equatable, Sendable {
    public let session: SessionDescriptor
    public let metrics: SessionEvaluationMetrics
    public let score: PresentationScoreReport
    public let startedAtMs: Int64
    public let endedAtMs: Int64

    public init(
        session: SessionDescriptor,
        metrics: SessionEvaluationMetrics,
        score: PresentationScoreReport,
        startedAtMs: Int64,
        endedAtMs: Int64
    ) {
        self.session = session
        self.metrics = metrics
        self.score = score
        self.startedAtMs = startedAtMs
        self.endedAtMs = endedAtMs
    }
}

public enum SessionReportBuilder {
    public static func build(from events: [PresentationEvent]) throws -> SessionReport {
        guard let started = events.first(where: { $0.kind == .sessionStarted }),
              case .session(let session) = started.payload else {
            throw SessionReportBuilderError.missingSessionStart
        }

        let ordered = events.sorted { $0.timestampMs < $1.timestampMs }
        let endedAtMs = ordered.last(where: { $0.kind == .sessionStopped })?.timestampMs
            ?? ordered.last?.timestampMs
            ?? started.timestampMs
        var speechSegments = ordered.compactMap { event -> SpeechSegment? in
            guard event.kind == .speechFinal, case .speech(let segment) = event.payload else { return nil }
            return segment
        }
        if speechSegments.isEmpty,
           let lastPartial = ordered.last(where: { $0.kind == .speechPartial }),
           case .speech(var segment) = lastPartial.payload {
            segment.endedAtMs = endedAtMs
            speechSegments = [segment]
        }
        let transcript = speechSegments.map(\.text).joined(separator: " ")
        let spokenMilliseconds = speechSegments.reduce(Int64(0)) { total, segment in
            total + max(0, (segment.endedAtMs ?? segment.startedAtMs) - segment.startedAtMs)
        }
        let characterCount = transcript.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }.count
        let spokenSeconds = Double(spokenMilliseconds) / 1_000

        let slides = ordered.compactMap { event -> SlideChange? in
            guard event.kind == .slideChanged, case .slideChange(let slide) = event.payload else { return nil }
            return slide
        }
        let uniqueSlides = Dictionary(slides.map { ($0.slideID, $0) }, uniquingKeysWith: { _, latest in latest })
        let metrics = SessionEvaluationMetrics(
            plannedDurationSeconds: session.plannedDurationSeconds,
            actualDurationSeconds: max(0, Int((endedAtMs - started.timestampMs) / 1_000)),
            spokenDurationSeconds: max(0, Int(spokenMilliseconds / 1_000)),
            fillerCount: countOccurrences(
                in: transcript,
                terms: ["えーっと", "えーと", "えっと", "ええと", "あのー", "そのー"]
            ),
            longSilenceCount: countLongSilences(in: ordered),
            averageCharactersPerSecond: spokenSeconds > 0 ? Double(characterCount) / spokenSeconds : 0,
            slideCount: uniqueSlides.count,
            denseSlideCount: uniqueSlides.values.filter { ($0.textDensity ?? 0) >= 0.72 }.count,
            structureMarkerCount: countOccurrences(
                in: transcript,
                terms: ["まず", "次に", "最後に", "結論", "まとめ", "first", "next", "finally"]
            ),
            audienceEngagementCueCount: countOccurrences(
                in: transcript,
                terms: ["でしょうか", "考えてみて", "想像して", "ご存じ", "?", "？"]
            )
        )
        return SessionReport(
            session: session,
            metrics: metrics,
            score: PresentationScorer().score(metrics),
            startedAtMs: started.timestampMs,
            endedAtMs: endedAtMs
        )
    }

    private static func countLongSilences(in events: [PresentationEvent]) -> Int {
        var wasLongSilence = false
        var count = 0
        for event in events {
            guard event.kind == .audioMetric,
                  case .audioMetric(let metric) = event.payload else { continue }
            let isLongSilence = !metric.isSpeech && metric.silenceDurationMs >= 2_500
            if isLongSilence && !wasLongSilence { count += 1 }
            wasLongSilence = isLongSilence
        }
        return count
    }

    private static func countOccurrences(in text: String, terms: [String]) -> Int {
        let normalized = text.lowercased()
        return terms.reduce(0) { total, term in
            total + normalized.components(separatedBy: term.lowercased()).count - 1
        }
    }
}

public enum SessionReportBuilderError: Error, Equatable {
    case missingSessionStart
}
