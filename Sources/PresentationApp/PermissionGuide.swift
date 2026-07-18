import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

enum PracticePermission: String, CaseIterable, Identifiable {
    case microphone
    case screenRecording

    var id: Self { self }
    var title: String { self == .microphone ? "マイク" : "画面収録" }
    var settingsPane: String { self == .microphone ? "Privacy_Microphone" : "Privacy_ScreenCapture" }
}

enum PermissionState: Equatable {
    case notDetermined
    case denied
    case restricted
    case granted

    var label: String {
        switch self {
        case .notDetermined: "未確認"
        case .denied: "許可されていません"
        case .restricted: "制限されています"
        case .granted: "許可済み"
        }
    }
}

@MainActor
protocol PermissionServicing {
    func state(for permission: PracticePermission) -> PermissionState
    func request(_ permission: PracticePermission) async -> PermissionState
    func openSettings(for permission: PracticePermission)
}

@MainActor
final class SystemPermissionService: PermissionServicing {
    private var screenRequestWasDenied = false

    func state(for permission: PracticePermission) -> PermissionState {
        switch permission {
        case .microphone:
            return switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: .notDetermined
            case .restricted: .restricted
            case .denied: .denied
            case .authorized: .granted
            @unknown default: .restricted
            }
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() { return .granted }
            return screenRequestWasDenied ? .denied : .notDetermined
        }
    }

    func request(_ permission: PracticePermission) async -> PermissionState {
        switch permission {
        case .microphone:
            guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
                showBundleRequiredAlert()
                return state(for: permission)
            }
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .screenRecording:
            screenRequestWasDenied = !CGRequestScreenCaptureAccess()
        }
        return state(for: permission)
    }

    func openSettings(for permission: PracticePermission) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsPane)"
        ) else { return }
        if !NSWorkspace.shared.open(url),
           let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    private func showBundleRequiredAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "開発用アプリから起動してください"
        alert.informativeText = "swift runではmacOSの権限を登録できません。ターミナルで ./scripts/run-app.sh を実行してから、もう一度お試しください。"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@MainActor
final class PermissionGuideViewModel: ObservableObject {
    @Published private(set) var states: [PracticePermission: PermissionState] = [:]
    @Published private(set) var requesting: PracticePermission?
    @Published private(set) var resultMessage: String?
    private let service: PermissionServicing

    init(service: PermissionServicing = SystemPermissionService()) {
        self.service = service
        refresh()
    }

    func refresh() {
        states = Dictionary(uniqueKeysWithValues: PracticePermission.allCases.map {
            ($0, service.state(for: $0))
        })
    }

    func request(_ permission: PracticePermission) async {
        guard requesting == nil else { return }
        requesting = permission
        let state = await service.request(permission)
        states[permission] = state
        switch state {
        case .granted:
            resultMessage = "\(permission.title)を許可しました。"
        case .denied:
            resultMessage = "\(permission.title)は許可されませんでした。システム設定から許可してください。"
        case .restricted:
            resultMessage = "\(permission.title)はこのMacの設定で制限されています。"
        case .notDetermined:
            resultMessage = "許可要求を完了できませんでした。開発用.appから起動しているか確認してください。"
        }
        requesting = nil
    }

    func openSettings(for permission: PracticePermission) {
        service.openSettings(for: permission)
        resultMessage = "システム設定で\(permission.title)を許可し、アプリへ戻って「状態を更新」を押してください。"
    }
}

private struct PermissionGuideView: View {
    @ObservedObject var viewModel: PermissionGuideViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("発表を見守るための権限")
                .font(.title2.bold())
            Text("音声への反応にはマイク、スライド解析には画面収録の許可が必要です。")
                .foregroundStyle(.secondary)

            ForEach(PracticePermission.allCases) { permission in
                HStack(spacing: 14) {
                    Image(systemName: permission == .microphone ? "mic.fill" : "rectangle.inset.filled")
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permission.title).font(.headline)
                        Text(viewModel.states[permission, default: .notDetermined].label)
                            .font(.caption)
                            .foregroundStyle(stateColor(for: permission))
                    }
                    Spacer()
                    if viewModel.states[permission] != .granted {
                        Button(primaryButtonTitle(for: permission)) {
                            if viewModel.states[permission] == .denied {
                                viewModel.openSettings(for: permission)
                            } else {
                                Task { await viewModel.request(permission) }
                            }
                        }
                        .disabled(viewModel.requesting != nil)
                        Button("設定を開く") { viewModel.openSettings(for: permission) }
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }

            if let resultMessage = viewModel.resultMessage {
                Text(resultMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("状態を更新") { viewModel.refresh() }
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func stateColor(for permission: PracticePermission) -> Color {
        viewModel.states[permission] == .granted ? .green : .orange
    }

    private func primaryButtonTitle(for permission: PracticePermission) -> String {
        viewModel.states[permission] == .denied ? "設定で許可" : "許可する"
    }
}

@MainActor
final class PermissionGuideWindowController: NSWindowController {
    let viewModel: PermissionGuideViewModel

    init(viewModel: PermissionGuideViewModel = PermissionGuideViewModel()) {
        self.viewModel = viewModel
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Presentation Coach — 権限"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PermissionGuideView(viewModel: viewModel))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        viewModel.refresh()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
