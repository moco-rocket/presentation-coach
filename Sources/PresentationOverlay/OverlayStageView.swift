import AppKit
import PresentationContracts
import SpriteKit
import SwiftUI

@MainActor
public struct OverlayStageView: View {
    @ObservedObject private var viewModel: OverlayViewModel
    @State private var scene: JudgeScene

    public init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel
        _scene = State(initialValue: JudgeScene(manifests: viewModel.judges.map(\.manifest)))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TransparentSpriteView(scene: scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let reaction = viewModel.activeReaction,
               let state = viewModel.judges.first(where: { $0.id == reaction.judgeID }) {
                SpeechBubble(reaction: reaction, manifest: state.manifest)
                    .id(reaction.id)
                    .transition(.scale(scale: 0.55, anchor: .bottom).combined(with: .opacity))
                    .padding(.top, 4)
            }

            if let timer = viewModel.timer {
                TimerPill(timer: timer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 16)
            }
        }
        .background(Color.clear)
        .onAppear { scene.update(states: viewModel.judges) }
        .onChange(of: viewModel.judges) { _, states in scene.update(states: states) }
        .animation(.spring(response: 0.28, dampingFraction: 0.62), value: viewModel.activeReaction?.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("発表審査員オーバーレイ")
    }
}

/// SwiftUI's `SpriteView` may install an opaque backing layer even when the
/// SpriteKit scene is clear. Owning the `SKView` lets every layer in the
/// window explicitly opt in to transparency.
private struct TransparentSpriteView: NSViewRepresentable {
    let scene: SKScene

    func makeNSView(context: Context) -> SKView {
        let view = TransparentSKView(frame: .zero)
        view.allowsTransparency = true
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: SKView, context: Context) {
        view.allowsTransparency = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        if view.scene !== scene {
            view.presentScene(scene)
        }
    }
}

private final class TransparentSKView: SKView {
    override var isOpaque: Bool { false }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

private struct SpeechBubble: View {
    let reaction: JudgeReaction
    let manifest: JudgeManifest

    var body: some View {
        VStack(spacing: 2) {
            Text(manifest.displayName)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(reaction.text)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .foregroundStyle(.black)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.22), radius: 0, x: 3, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.black, lineWidth: 3)
        )
        .frame(maxWidth: 360)
        .accessibilityLabel("\(manifest.displayName)、\(reaction.text)")
    }
}

private struct TimerPill: View {
    let timer: TimerUpdate

    var body: some View {
        Text(formattedRemaining)
            .font(.system(size: 15, weight: .black, design: .monospaced))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(timer.remainingSeconds <= 30 ? .white : .black)
            .background(timer.remainingSeconds <= 30 ? Color.red : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.black, lineWidth: 2))
    }

    private var formattedRemaining: String {
        let seconds = max(0, timer.remainingSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Hosts the overlay at the bottom of the selected screen. The window can be
/// made interactive later; the practice default deliberately passes clicks to
/// the presentation underneath.
@MainActor
public final class OverlayPanelController {
    public let panel: NSPanel

    public init(viewModel: OverlayViewModel, screen: NSScreen? = .main) {
        let targetFrame = screen?.visibleFrame ?? .zero
        let height: CGFloat = 230
        let frame = CGRect(
            x: targetFrame.minX,
            y: targetFrame.minY,
            width: targetFrame.width,
            height: height
        )
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        let hostingView = TransparentHostingView(rootView: OverlayStageView(viewModel: viewModel))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    public func show() {
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }
}
