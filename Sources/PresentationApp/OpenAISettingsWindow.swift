import AppKit
import PresentationFeedback
import SwiftUI

@MainActor
final class OpenAISettingsViewModel: ObservableObject {
    @Published var apiKey = ""
    @Published private(set) var hasStoredKey = false
    @Published private(set) var message: String?
    private let store: any OpenAICredentialStoring
    private let environment: [String: String]

    init(
        store: any OpenAICredentialStoring = KeychainOpenAICredentialStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.store = store
        self.environment = environment
        refresh()
    }

    var environmentKeyIsActive: Bool {
        !(environment["OPENAI_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var statusText: String {
        if environmentKeyIsActive { return "環境変数 OPENAI_API_KEY を使用します" }
        if hasStoredKey { return "KeychainのAPIキーを使用します" }
        return "LLMコメントは未設定です（ルールコメントは動作します）"
    }

    func refresh() {
        do {
            hasStoredKey = try store.loadAPIKey() != nil
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func save() {
        do {
            try store.saveAPIKey(apiKey)
            apiKey = ""
            hasStoredKey = true
            message = "APIキーをKeychainへ保存しました。次の練習から使用します。"
        } catch {
            message = error.localizedDescription
        }
    }

    func remove() {
        do {
            try store.deleteAPIKey()
            apiKey = ""
            hasStoredKey = false
            message = "KeychainのAPIキーを削除しました。"
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct OpenAISettingsView: View {
    @ObservedObject var viewModel: OpenAISettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LLMコメント設定")
                .font(.system(size: 24, weight: .black, design: .rounded))
            Text(viewModel.statusText)
                .foregroundStyle(viewModel.environmentKeyIsActive || viewModel.hasStoredKey ? .green : .secondary)

            SecureField("OpenAI APIキー", text: $viewModel.apiKey)
                .textFieldStyle(.roundedBorder)
            Text("キーはmacOS Keychainに保存され、発表記録やログには含めません。環境変数がある場合はそちらを優先します。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message = viewModel.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                if viewModel.hasStoredKey {
                    Button("保存済みキーを削除", role: .destructive) { viewModel.remove() }
                }
                Spacer()
                Button("Keychainへ保存") { viewModel.save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 280)
    }
}

@MainActor
final class OpenAISettingsWindowController: NSWindowController {
    let viewModel: OpenAISettingsViewModel

    init(viewModel: OpenAISettingsViewModel = OpenAISettingsViewModel()) {
        self.viewModel = viewModel
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Presentation Coach — LLM設定"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OpenAISettingsView(viewModel: viewModel))
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
