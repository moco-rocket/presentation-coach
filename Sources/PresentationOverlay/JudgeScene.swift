import AppKit
import PresentationContracts
import SpriteKit

@MainActor
public final class JudgeScene: SKScene {
    private var characterNodes: [JudgeID: JudgeNode] = [:]
    private var manifests: [JudgeManifest] = []

    public init(manifests: [JudgeManifest]) {
        self.manifests = manifests.sorted { $0.stageSlot < $1.stageSlot }
        super.init(size: CGSize(width: 960, height: 190))
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = CGPoint(x: 0, y: 0)
        rebuildCharacters()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutCharacters()
    }

    public func update(states: [JudgeViewState]) {
        for state in states {
            characterNodes[state.id]?.setEmotion(state.emotion, animated: true)
        }
    }

    private func rebuildCharacters() {
        removeAllChildren()
        characterNodes.removeAll()
        for manifest in manifests {
            let node = JudgeNode(manifest: manifest)
            characterNodes[manifest.id] = node
            addChild(node)
        }
        layoutCharacters()
    }

    private func layoutCharacters() {
        guard !manifests.isEmpty else { return }
        let slotWidth = size.width / CGFloat(manifests.count)
        for (index, manifest) in manifests.enumerated() {
            characterNodes[manifest.id]?.position = CGPoint(
                x: slotWidth * (CGFloat(index) + 0.5),
                y: min(70, size.height * 0.42)
            )
        }
    }
}

enum JudgeArtworkSheet {
    static let filename = "judges-expression-sheet-v1"
    static let columnCount = 5
    static let rowCount = 4

    static func normalizedRect(for judgeID: JudgeID, emotion: ReactionEmotion) -> CGRect {
        let rowFromTop: Int
        switch judgeID {
        case .tempo: rowFromTop = 0
        case .clarity: rowFromTop = 1
        case .slide: rowFromTop = 2
        case .audience: rowFromTop = 3
        }

        let column: Int
        switch emotion {
        case .idle: column = 0
        case .happy, .impressed: column = 1
        case .curious: column = 2
        case .confused, .panic: column = 3
        case .sleepy: column = 4
        }

        return CGRect(
            x: CGFloat(column) / CGFloat(columnCount),
            y: CGFloat(rowCount - rowFromTop - 1) / CGFloat(rowCount),
            width: 1 / CGFloat(columnCount),
            height: 1 / CGFloat(rowCount)
        )
    }

    @MainActor
    static func texture(for judgeID: JudgeID, emotion: ReactionEmotion) -> SKTexture? {
        guard let sheetTexture else { return nil }
        let texture = SKTexture(rect: normalizedRect(for: judgeID, emotion: emotion), in: sheetTexture)
        texture.filteringMode = .linear
        return texture
    }

    @MainActor
    private static let sheetTexture: SKTexture? = {
        let url = Bundle.module.url(
            forResource: filename,
            withExtension: "png",
            subdirectory: "Judges"
        ) ?? Bundle.module.url(forResource: filename, withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()
}

@MainActor
private final class JudgeNode: SKNode {
    private let judgeID: JudgeID
    private let bodyNode: SKShapeNode
    private let leftEye = SKShapeNode(circleOfRadius: 4)
    private let rightEye = SKShapeNode(circleOfRadius: 4)
    private let mouth = SKShapeNode()
    private let roleLabel: SKLabelNode
    private let artworkNode: SKSpriteNode?
    private var emotion: ReactionEmotion = .idle

    init(manifest: JudgeManifest) {
        judgeID = manifest.id
        bodyNode = SKShapeNode(rectOf: CGSize(width: 112, height: 92), cornerRadius: 30)
        roleLabel = SKLabelNode(text: manifest.displayName)
        if let texture = JudgeArtworkSheet.texture(for: manifest.id, emotion: .idle) {
            artworkNode = SKSpriteNode(texture: texture, size: CGSize(width: 190, height: 158))
        } else {
            artworkNode = nil
        }
        super.init()

        bodyNode.fillColor = NSColor(hex: manifest.themeColorHex) ?? .systemPink
        bodyNode.strokeColor = .labelColor
        bodyNode.lineWidth = 5
        bodyNode.isHidden = artworkNode != nil
        addChild(bodyNode)

        for eye in [leftEye, rightEye] {
            eye.fillColor = .labelColor
            eye.strokeColor = .clear
            bodyNode.addChild(eye)
        }
        leftEye.position = CGPoint(x: -22, y: 12)
        rightEye.position = CGPoint(x: 22, y: 12)

        mouth.strokeColor = .labelColor
        mouth.lineWidth = 4
        mouth.lineCap = .round
        bodyNode.addChild(mouth)

        if let artworkNode {
            artworkNode.position = CGPoint(x: 0, y: 8)
            addChild(artworkNode)
        }

        roleLabel.fontName = "HiraginoSans-W6"
        roleLabel.fontSize = 15
        roleLabel.fontColor = .labelColor
        roleLabel.verticalAlignmentMode = .center
        roleLabel.position = CGPoint(x: 0, y: -66)
        addChild(roleLabel)

        setEmotion(.idle, animated: false)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEmotion(_ newEmotion: ReactionEmotion, animated: Bool) {
        guard newEmotion != emotion || !animated else { return }
        emotion = newEmotion
        artworkNode?.texture = JudgeArtworkSheet.texture(for: judgeID, emotion: newEmotion)
        mouth.path = mouthPath(for: newEmotion)

        leftEye.yScale = newEmotion == .sleepy ? 0.18 : 1
        rightEye.yScale = newEmotion == .sleepy ? 0.18 : 1

        guard animated else { return }
        removeAction(forKey: "reaction")
        let action: SKAction
        switch newEmotion {
        case .happy, .impressed:
            action = .sequence([.scale(to: 1.14, duration: 0.09), .scale(to: 1, duration: 0.2)])
        case .curious, .confused:
            action = .sequence([
                .rotate(byAngle: 0.12, duration: 0.09),
                .rotate(byAngle: -0.24, duration: 0.16),
                .rotate(byAngle: 0.12, duration: 0.09)
            ])
        case .panic:
            action = .sequence([
                .moveBy(x: -7, y: 0, duration: 0.045),
                .moveBy(x: 14, y: 0, duration: 0.09),
                .moveBy(x: -7, y: 0, duration: 0.045)
            ])
        case .sleepy:
            action = .sequence([.moveBy(x: 0, y: -5, duration: 0.2), .moveBy(x: 0, y: 5, duration: 0.3)])
        case .idle:
            action = .scale(to: 1, duration: 0.12)
        }
        run(action, withKey: "reaction")
    }

    private func mouthPath(for emotion: ReactionEmotion) -> CGPath {
        let path = CGMutablePath()
        switch emotion {
        case .happy, .impressed:
            path.move(to: CGPoint(x: -18, y: -10))
            path.addQuadCurve(to: CGPoint(x: 18, y: -10), control: CGPoint(x: 0, y: -28))
        case .panic, .confused:
            path.addEllipse(in: CGRect(x: -8, y: -22, width: 16, height: 22))
        case .sleepy:
            path.move(to: CGPoint(x: -13, y: -16))
            path.addLine(to: CGPoint(x: 13, y: -16))
        case .curious:
            path.move(to: CGPoint(x: -14, y: -14))
            path.addQuadCurve(to: CGPoint(x: 14, y: -11), control: CGPoint(x: 0, y: -4))
        case .idle:
            path.move(to: CGPoint(x: -13, y: -15))
            path.addQuadCurve(to: CGPoint(x: 13, y: -15), control: CGPoint(x: 0, y: -19))
        }
        return path
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((number >> 16) & 0xff) / 255,
            green: CGFloat((number >> 8) & 0xff) / 255,
            blue: CGFloat(number & 0xff) / 255,
            alpha: 1
        )
    }
}
