import Foundation
import PresentationCapture
import PresentationContracts
import PresentationFeedback
import PresentationOverlay

@main
enum PresentationAppMain {
    static func main() async throws {
        if CommandLine.arguments.contains("--demo") {
            let result = try await PresentationDemo.run()
            print("\(result.judgeID.rawValue): \(result.comment)")
            print(String(format: "score: %.1f / %.1f", result.score, result.maximumScore))
            print("events: \(result.recordingURL.path)")
            return
        }

        print("Presentation Coach prototype")
        print("Run `swift run PresentationApp --demo` for the integrated event demo.")
    }
}
