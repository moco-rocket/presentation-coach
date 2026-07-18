import Foundation
import ScreenCaptureKit

public struct CapturableDisplay: Equatable, Identifiable, Sendable {
    public var id: UInt32
    public var width: Int
    public var height: Int

    public init(id: UInt32, width: Int, height: Int) {
        self.id = id
        self.width = width
        self.height = height
    }
}

public enum ScreenSourceCatalog {
    public static func availableDisplays() async throws -> [CapturableDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        return content.displays.map {
            CapturableDisplay(id: $0.displayID, width: $0.width, height: $0.height)
        }
    }
}
