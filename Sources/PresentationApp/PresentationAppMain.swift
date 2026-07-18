import AppKit
import Foundation
import PresentationCapture
import PresentationContracts
import PresentationFeedback
import PresentationOverlay

@main
enum PresentationAppMain {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--demo") {
            let result = try await PresentationDemo.run()
            print("\(result.judgeID.rawValue): \(result.comment)")
            print(String(format: "score: %.1f / %.1f", result.score, result.maximumScore))
            print("events: \(result.recordingURL.path)")
            return
        }

        let configuration = try ApplicationConfiguration(arguments: arguments)
        try await MainActor.run {
            let application = try PresentationMacApplication(configuration: configuration)
            application.run()
        }
    }
}
