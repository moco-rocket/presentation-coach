import PresentationCapture
import Testing
@testable import PresentationApp

@MainActor
@Test func practiceSetupBuildsDescriptorAndSelectedDisplay() throws {
    let viewModel = PracticeSetupViewModel()
    viewModel.title = " 新製品発表 "
    viewModel.goal = "承認"
    viewModel.audience = "経営陣"
    viewModel.durationMinutes = 7
    viewModel.displays = [CaptureDisplay(
        id: 42,
        name: "外部ディスプレイ",
        width: 1_920,
        height: 1_080,
        isMain: false
    )]
    viewModel.selectedDisplayID = 42

    let setup = try #require(viewModel.makeSetup())

    #expect(setup.descriptor.title == "新製品発表")
    #expect(setup.descriptor.goal == "承認")
    #expect(setup.descriptor.audience == "経営陣")
    #expect(setup.descriptor.plannedDurationSeconds == 420)
    #expect(setup.displayID == 42)
}

@MainActor
@Test func practiceSetupRequiresTitleAndDisplay() {
    let viewModel = PracticeSetupViewModel()
    viewModel.title = "  "
    viewModel.selectedDisplayID = nil

    #expect(!viewModel.canStart)
    #expect(viewModel.makeSetup() == nil)
}
