import Foundation
import PresentationContracts

public actor SessionEventHub {
    public let sessionID: UUID
    public let eventBus: PresentationEventBus

    private let recorder: JSONLEventRecorder?
    private let clock = ContinuousClock()
    private var startedAt: ContinuousClock.Instant?
    private var isActive = false

    public init(
        sessionID: UUID = UUID(),
        eventBus: PresentationEventBus = PresentationEventBus(),
        recordingURL: URL? = nil
    ) {
        self.sessionID = sessionID
        self.eventBus = eventBus
        self.recorder = recordingURL.map(JSONLEventRecorder.init(url:))
    }

    public func events(bufferingNewest limit: Int = 256) async -> AsyncStream<PresentationEvent> {
        await eventBus.stream(bufferingNewest: limit)
    }

    @discardableResult
    public func start(descriptor: SessionDescriptor) async throws -> PresentationEvent {
        guard !isActive else {
            throw SessionEventHubError.alreadyStarted
        }
        startedAt = clock.now
        isActive = true
        return try await emit(
            kind: .sessionStarted,
            payload: .session(descriptor),
            timestampMs: 0
        )
    }

    @discardableResult
    public func emit(
        kind: PresentationEventKind,
        payload: PresentationEventPayload,
        timestampMs: Int64? = nil
    ) async throws -> PresentationEvent {
        guard isActive || kind == .sessionStarted else {
            throw SessionEventHubError.notStarted
        }

        let event = PresentationEvent(
            sessionID: sessionID,
            timestampMs: timestampMs ?? elapsedMilliseconds,
            kind: kind,
            payload: payload
        )
        try await recorder?.append(event)
        await eventBus.publish(event)
        return event
    }

    @discardableResult
    public func stop() async throws -> PresentationEvent {
        guard isActive else {
            throw SessionEventHubError.notStarted
        }
        let event = try await emit(kind: .sessionStopped, payload: .none)
        isActive = false
        try await recorder?.close()
        await eventBus.finish()
        return event
    }

    private var elapsedMilliseconds: Int64 {
        guard let startedAt else { return 0 }
        let components = startedAt.duration(to: clock.now).components
        return Int64(components.seconds) * 1_000
            + Int64(components.attoseconds / 1_000_000_000_000_000)
    }
}

public enum SessionEventHubError: Error, Equatable {
    case alreadyStarted
    case notStarted
}
