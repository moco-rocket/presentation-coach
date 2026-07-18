import AppKit
import CoreGraphics
import PresentationCapture
import PresentationContracts
import SwiftUI

struct PracticeSetup: Equatable, Sendable {
    var descriptor: SessionDescriptor
    var displayID: UInt32
}

@MainActor
final class PracticeSetupViewModel: ObservableObject {
    @Published var title = "発表練習"
    @Published var goal = ""
    @Published var audience = ""
    @Published var durationMinutes = 5
    @Published var displays: [CaptureDisplay] = []
    @Published var selectedDisplayID: UInt32?
    @Published private(set) var isLoadingDisplays = false
    @Published private(set) var errorMessage: String?

    var canStart: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedDisplayID != nil
            && !isLoadingDisplays
    }

    func loadDisplays() async {
        isLoadingDisplays = true
        defer { isLoadingDisplays = false }
        do {
            displays = try await ScreenCaptureSource.availableDisplays()
            if !displays.contains(where: { $0.id == selectedDisplayID }) {
                selectedDisplayID = displays.first(where: \.isMain)?.id ?? displays.first?.id
            }
            errorMessage = displays.isEmpty ? "利用できるディスプレイがありません。" : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func makeSetup() -> PracticeSetup? {
        guard canStart, let displayID = selectedDisplayID else { return nil }
        return PracticeSetup(
            descriptor: SessionDescriptor(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                audience: audience.trimmingCharacters(in: .whitespacesAndNewlines),
                plannedDurationSeconds: durationMinutes * 60
            ),
            displayID: displayID
        )
    }
}

private struct PracticeSetupView: View {
    @ObservedObject var viewModel: PracticeSetupViewModel
    let onStart: (PracticeSetup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("練習の準備")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                Text("審査員に見てほしい発表と画面を選びます。")
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("発表名", text: $viewModel.title)
                TextField("今回の目標", text: $viewModel.goal)
                TextField("想定する聴衆", text: $viewModel.audience)
                Stepper("予定時間: \(viewModel.durationMinutes)分", value: $viewModel.durationMinutes, in: 1...120)
                Picker("監視する画面", selection: $viewModel.selectedDisplayID) {
                    ForEach(viewModel.displays) { display in
                        Text("\(display.name)（\(display.width)×\(display.height)）")
                            .tag(Optional(display.id))
                    }
                }
                .disabled(viewModel.isLoadingDisplays)
            }
            .formStyle(.grouped)

            if viewModel.isLoadingDisplays {
                ProgressView("画面を確認中…")
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("画面を再読み込み") { Task { await viewModel.loadDisplays() } }
                Spacer()
                Button("発表を開始") {
                    if let setup = viewModel.makeSetup() { onStart(setup) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStart)
            }
        }
        .padding(24)
        .frame(width: 540, height: 450)
    }
}

@MainActor
final class PracticeSetupWindowController: NSWindowController {
    let viewModel: PracticeSetupViewModel

    init(
        viewModel: PracticeSetupViewModel = PracticeSetupViewModel(),
        onStart: @escaping (PracticeSetup) -> Void
    ) {
        self.viewModel = viewModel
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 540, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Presentation Coach — 練習の準備"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: PracticeSetupView(viewModel: viewModel) { [weak self] setup in
            self?.close()
            onStart(setup)
        })
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { await viewModel.loadDisplays() }
    }
}
