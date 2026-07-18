import Foundation

enum ApplicationMode: Equatable {
    case idle
    case uiDemo
}

struct ApplicationConfiguration: Equatable {
    var mode: ApplicationMode
    var fixtureURL: URL?
    var playbackSpeed: Double

    init(arguments: [String], currentDirectoryURL: URL? = nil) throws {
        let directory = currentDirectoryURL
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        mode = arguments.contains("--ui-demo") ? .uiDemo : .idle
        playbackSpeed = 1
        fixtureURL = nil

        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--ui-demo":
                break

            case "--fixture":
                index += 1
                guard index < arguments.count else {
                    throw ApplicationConfigurationError.missingValue("--fixture")
                }
                fixtureURL = URL(fileURLWithPath: arguments[index], relativeTo: directory)
                    .standardizedFileURL

            case "--ui-demo-speed":
                index += 1
                guard index < arguments.count else {
                    throw ApplicationConfigurationError.missingValue("--ui-demo-speed")
                }
                guard let speed = Double(arguments[index]), speed.isFinite, speed > 0 else {
                    throw ApplicationConfigurationError.invalidPlaybackSpeed(arguments[index])
                }
                playbackSpeed = speed

            default:
                throw ApplicationConfigurationError.unknownArgument(arguments[index])
            }
            index += 1
        }

        if mode == .uiDemo, fixtureURL == nil {
            fixtureURL = directory
                .appendingPathComponent("Fixtures/Sessions/ui-demo.jsonl")
                .standardizedFileURL
        }
    }
}

enum ApplicationConfigurationError: Error, LocalizedError, Equatable {
    case unknownArgument(String)
    case missingValue(String)
    case invalidPlaybackSpeed(String)

    var errorDescription: String? {
        switch self {
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        case .missingValue(let argument):
            return "Missing value for \(argument)"
        case .invalidPlaybackSpeed(let value):
            return "Invalid UI demo speed: \(value)"
        }
    }
}
