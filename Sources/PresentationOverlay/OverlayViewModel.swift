import Combine
import Foundation
import PresentationContracts

public struct JudgeViewState: Equatable, Identifiable, Sendable {
    public var id: JudgeID { manifest.id }
    public var manifest: JudgeManifest
    public var emotion: ReactionEmotion
    public var reaction: JudgeReaction?

    public init(
        manifest: JudgeManifest,
        emotion: ReactionEmotion = .idle,
        reaction: JudgeReaction? = nil
    ) {
        self.manifest = manifest
        self.emotion = emotion
        self.reaction = reaction
    }
}

@MainActor
public final class OverlayViewModel: ObservableObject {
    @Published public private(set) var judges: [JudgeViewState]
    @Published public private(set) var activeReaction: JudgeReaction?
    @Published public private(set) var timer: TimerUpdate?
    @Published public private(set) var isSessionRunning = false

    private var dismissalTask: Task<Void, Never>?
    private let automaticallyDismissReactions: Bool

    public init(
        manifests: [JudgeManifest]? = nil,
        automaticallyDismissReactions: Bool = true
    ) {
        let resolved = manifests ?? (try? JudgeManifestLoader.bundled()) ?? []
        judges = resolved
            .sorted { $0.stageSlot < $1.stageSlot }
            .map { JudgeViewState(manifest: $0) }
        self.automaticallyDismissReactions = automaticallyDismissReactions
    }

    deinit {
        dismissalTask?.cancel()
    }

    public func consume(_ event: PresentationEvent) {
        switch (event.kind, event.payload) {
        case (.sessionStarted, .session):
            isSessionRunning = true

        case (.sessionStopped, _):
            isSessionRunning = false
            clearReaction()

        case (.timerUpdated, .timer(let update)):
            timer = update

        case (.judgeReaction, .judgeReaction(let reaction)):
            show(reaction)

        default:
            break
        }
    }

    public func show(_ reaction: JudgeReaction) {
        dismissalTask?.cancel()

        if let previous = activeReaction,
           let previousIndex = judges.firstIndex(where: { $0.id == previous.judgeID }) {
            judges[previousIndex].emotion = .idle
            judges[previousIndex].reaction = nil
        }

        activeReaction = reaction
        if let index = judges.firstIndex(where: { $0.id == reaction.judgeID }) {
            judges[index].emotion = reaction.emotion
            judges[index].reaction = reaction
        }

        guard automaticallyDismissReactions else { return }
        let reactionID = reaction.id
        let duration = max(0, reaction.durationMs)
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(duration))
            guard !Task.isCancelled else { return }
            self?.clearReaction(ifMatching: reactionID)
        }
    }

    public func clearReaction() {
        clearReaction(ifMatching: nil)
    }

    private func clearReaction(ifMatching reactionID: UUID?) {
        if let reactionID, activeReaction?.id != reactionID { return }
        dismissalTask?.cancel()
        dismissalTask = nil

        if let activeReaction,
           let index = judges.firstIndex(where: { $0.id == activeReaction.judgeID }) {
            judges[index].emotion = .idle
            judges[index].reaction = nil
        }
        activeReaction = nil
    }
}
