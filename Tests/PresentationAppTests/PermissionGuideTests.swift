import Testing
@testable import PresentationApp

@MainActor
private final class PermissionServiceStub: PermissionServicing {
    var states: [PracticePermission: PermissionState] = [
        .microphone: .notDetermined,
        .screenRecording: .denied
    ]
    var requested: [PracticePermission] = []
    var openedSettings: [PracticePermission] = []

    func state(for permission: PracticePermission) -> PermissionState {
        states[permission, default: .notDetermined]
    }

    func request(_ permission: PracticePermission) async -> PermissionState {
        requested.append(permission)
        states[permission] = .granted
        return .granted
    }

    func openSettings(for permission: PracticePermission) {
        openedSettings.append(permission)
    }
}

@MainActor
@Test func permissionGuideLoadsAndRefreshesStates() {
    let service = PermissionServiceStub()
    let viewModel = PermissionGuideViewModel(service: service)

    #expect(viewModel.states[.microphone] == .notDetermined)
    #expect(viewModel.states[.screenRecording] == .denied)

    service.states[.microphone] = .granted
    viewModel.refresh()
    #expect(viewModel.states[.microphone] == .granted)
}

@MainActor
@Test func permissionGuideRequestsAndOpensSettings() async {
    let service = PermissionServiceStub()
    let viewModel = PermissionGuideViewModel(service: service)

    await viewModel.request(.microphone)
    viewModel.openSettings(for: .screenRecording)

    #expect(service.requested == [.microphone])
    #expect(service.openedSettings == [.screenRecording])
    #expect(viewModel.states[.microphone] == .granted)
    #expect(viewModel.requesting == nil)
}
