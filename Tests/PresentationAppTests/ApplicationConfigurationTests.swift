import Foundation
import Testing
@testable import PresentationApp

@Test func defaultConfigurationStartsIdleApplication() throws {
    let configuration = try ApplicationConfiguration(
        arguments: [],
        currentDirectoryURL: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
    )

    #expect(configuration.mode == .idle)
    #expect(configuration.fixtureURL == nil)
    #expect(configuration.playbackSpeed == 1)
}

@Test func uiDemoUsesCheckedInFixtureByDefault() throws {
    let directory = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
    let configuration = try ApplicationConfiguration(
        arguments: ["--ui-demo", "--ui-demo-speed", "4"],
        currentDirectoryURL: directory
    )

    #expect(configuration.mode == .uiDemo)
    #expect(configuration.fixtureURL == directory.appendingPathComponent("Fixtures/Sessions/ui-demo.jsonl"))
    #expect(configuration.playbackSpeed == 4)
}

@Test func explicitFixtureIsResolvedRelativeToCurrentDirectory() throws {
    let directory = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
    let configuration = try ApplicationConfiguration(
        arguments: ["--ui-demo", "--fixture", "Fixtures/custom.jsonl"],
        currentDirectoryURL: directory
    )

    #expect(configuration.fixtureURL == directory.appendingPathComponent("Fixtures/custom.jsonl"))
}

@Test func invalidArgumentsAreRejected() {
    #expect(throws: ApplicationConfigurationError.unknownArgument("--wat")) {
        try ApplicationConfiguration(arguments: ["--wat"])
    }
    #expect(throws: ApplicationConfigurationError.invalidPlaybackSpeed("0")) {
        try ApplicationConfiguration(arguments: ["--ui-demo", "--ui-demo-speed", "0"])
    }
}
