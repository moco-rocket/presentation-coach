import Foundation
import PresentationContracts

public actor PresentationEventBus {
    private var continuations: [UUID: AsyncStream<PresentationEvent>.Continuation] = [:]

    public init() {}

    public func stream(bufferingNewest limit: Int = 256) -> AsyncStream<PresentationEvent> {
        let subscriberID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(limit)) { continuation in
            continuations[subscriberID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeSubscriber(subscriberID)
                }
            }
        }
    }

    public func publish(_ event: PresentationEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func removeSubscriber(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
