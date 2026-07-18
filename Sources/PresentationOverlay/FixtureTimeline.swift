import Foundation
import PresentationContracts

public enum FixtureTimelineError: Error, Equatable {
    case invalidSpeed
    case invalidLine(number: Int, message: String)
}

/// Replays UI events using their relative timestamps. The consumer receives the
/// same `PresentationEvent` values whether the source is a fixture or a live bus.
@MainActor
public final class FixtureTimeline {
    public let events: [PresentationEvent]
    private var playbackTimers: [Timer] = []

    public init(events: [PresentationEvent]) {
        self.events = events.sorted { lhs, rhs in
            if lhs.timestampMs == rhs.timestampMs {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestampMs < rhs.timestampMs
        }
    }

    public convenience init(jsonLines: String) throws {
        let decoder = JSONDecoder()
        var decoded: [PresentationEvent] = []

        for (offset, rawLine) in jsonLines.split(whereSeparator: { $0.isNewline }).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            do {
                decoded.append(try decoder.decode(PresentationEvent.self, from: Data(line.utf8)))
            } catch {
                throw FixtureTimelineError.invalidLine(number: offset + 1, message: error.localizedDescription)
            }
        }
        self.init(events: decoded)
    }

    public convenience init(contentsOf url: URL) throws {
        try self.init(jsonLines: String(contentsOf: url, encoding: .utf8))
    }

    public func play(
        speed: Double = 1,
        onEvent: @escaping @MainActor (PresentationEvent) -> Void
    ) throws {
        guard speed.isFinite, speed > 0 else { throw FixtureTimelineError.invalidSpeed }
        stop()

        let origin = events.first?.timestampMs ?? 0
        playbackTimers = events.map { event in
            let delayMilliseconds = Double(max(0, event.timestampMs - origin)) / speed
            let timer = Timer(timeInterval: delayMilliseconds / 1_000, repeats: false) { _ in
                MainActor.assumeIsolated {
                    onEvent(event)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        }
    }

    /// Deterministic, delay-free playback for previews and unit tests.
    public func replayImmediately(
        onEvent: @MainActor (PresentationEvent) -> Void
    ) {
        events.forEach(onEvent)
    }

    public func stop() {
        playbackTimers.forEach { $0.invalidate() }
        playbackTimers.removeAll()
    }

}
