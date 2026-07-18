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
    var requestResult: PermissionState = .granted

    func state(for permission: PracticePermission) -> PermissionState {
        states[permission, default: .notDetermined]
    }

    func request(_ permission: PracticePermission) async -> PermissionState {
        requested.append(permission)
        states[permission] = requestResult
        return requestResult
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
    #expect(viewModel.resultMessage == "マイクを許可しました。")

    viewModel.openSettings(for: .screenRecording)

    #expect(service.requested == [.microphone])
    #expect(service.openedSettings == [.screenRecording])
    #expect(viewModel.states[.microphone] == .granted)
    #expect(viewModel.resultMessage == "システム設定で画面収録を許可し、アプリへ戻って「状態を更新」を押してください。")
    #expect(viewModel.requesting == nil)
}

@MainActor
@Test func permissionGuideExplainsDeniedRequest() async {
    let service = PermissionServiceStub()
    service.states[.screenRecording] = .denied
    service.requestResult = .denied
    let viewModel = PermissionGuideViewModel(service: service)

    await viewModel.request(.screenRecording)

    #expect(viewModel.resultMessage == "画面収録は許可されませんでした。システム設定から許可してください。")
}
