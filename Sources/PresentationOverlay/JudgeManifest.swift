import Foundation
import PresentationContracts

public struct NormalizedPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Data-only description of a judge. Artwork can replace the placeholder scene
/// without changing the event contract or the overlay view model.
public struct JudgeManifest: Codable, Equatable, Identifiable, Sendable {
    public var id: JudgeID
    public var displayName: String
    public var role: String
    public var themeColorHex: String
    public var accentColorHex: String
    public var stageSlot: Int
    public var bubbleAnchor: NormalizedPoint
    public var animations: [ReactionEmotion: String]
    public var soundIDs: [ReactionEmotion: String]

    public init(
        id: JudgeID,
        displayName: String,
        role: String,
        themeColorHex: String,
        accentColorHex: String,
        stageSlot: Int,
        bubbleAnchor: NormalizedPoint,
        animations: [ReactionEmotion: String],
        soundIDs: [ReactionEmotion: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.themeColorHex = themeColorHex
        self.accentColorHex = accentColorHex
        self.stageSlot = stageSlot
        self.bubbleAnchor = bubbleAnchor
        self.animations = animations
        self.soundIDs = soundIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case role
        case themeColorHex
        case accentColorHex
        case stageSlot
        case bubbleAnchor
        case animations
        case soundIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(JudgeID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        role = try container.decode(String.self, forKey: .role)
        themeColorHex = try container.decode(String.self, forKey: .themeColorHex)
        accentColorHex = try container.decode(String.self, forKey: .accentColorHex)
        stageSlot = try container.decode(Int.self, forKey: .stageSlot)
        bubbleAnchor = try container.decode(NormalizedPoint.self, forKey: .bubbleAnchor)
        animations = Self.decodeEmotionMap(
            try container.decode([String: String].self, forKey: .animations)
        )
        soundIDs = Self.decodeEmotionMap(
            try container.decodeIfPresent([String: String].self, forKey: .soundIDs) ?? [:]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(role, forKey: .role)
        try container.encode(themeColorHex, forKey: .themeColorHex)
        try container.encode(accentColorHex, forKey: .accentColorHex)
        try container.encode(stageSlot, forKey: .stageSlot)
        try container.encode(bubbleAnchor, forKey: .bubbleAnchor)
        try container.encode(Self.encodeEmotionMap(animations), forKey: .animations)
        try container.encode(Self.encodeEmotionMap(soundIDs), forKey: .soundIDs)
    }

    private static func decodeEmotionMap(_ raw: [String: String]) -> [ReactionEmotion: String] {
        Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            ReactionEmotion(rawValue: key).map { ($0, value) }
        })
    }

    private static func encodeEmotionMap(_ map: [ReactionEmotion: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
    }
}

public enum JudgeManifestLoader {
    public static func bundled() throws -> [JudgeManifest] {
        let decoder = JSONDecoder()
        let manifests = try JudgeID.allCases.map { judgeID in
            let url = Bundle.module.url(
                forResource: judgeID.rawValue,
                withExtension: "json",
                subdirectory: "Judges"
            ) ?? Bundle.module.url(forResource: judgeID.rawValue, withExtension: "json")
            guard let url else {
                throw JudgeManifestError.missingResource(judgeID.rawValue)
            }
            return try decoder.decode(JudgeManifest.self, from: Data(contentsOf: url))
        }
        return manifests.sorted { $0.stageSlot < $1.stageSlot }
    }
}

public enum JudgeManifestError: Error, Equatable {
    case missingResource(String)
}
