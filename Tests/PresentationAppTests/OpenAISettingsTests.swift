import PresentationFeedback
import Testing
@testable import PresentationApp

private final class SettingsCredentialStore: OpenAICredentialStoring, @unchecked Sendable {
    var key: String?
    init(key: String? = nil) { self.key = key }
    func loadAPIKey() throws -> String? { key }
    func saveAPIKey(_ key: String) throws { self.key = key }
    func deleteAPIKey() throws { key = nil }
}

@MainActor
@Test func openAISettingsSavesAndRemovesKeychainCredential() {
    let store = SettingsCredentialStore()
    let viewModel = OpenAISettingsViewModel(store: store, environment: [:])
    viewModel.apiKey = " secret-key "

    viewModel.save()

    #expect(store.key == " secret-key ")
    #expect(viewModel.hasStoredKey)
    #expect(viewModel.apiKey.isEmpty)

    viewModel.remove()
    #expect(store.key == nil)
    #expect(!viewModel.hasStoredKey)
}

@MainActor
@Test func openAISettingsExplainsEnvironmentPrecedence() {
    let viewModel = OpenAISettingsViewModel(
        store: SettingsCredentialStore(key: "stored"),
        environment: ["OPENAI_API_KEY": "environment"]
    )
    #expect(viewModel.environmentKeyIsActive)
    #expect(viewModel.statusText.contains("環境変数"))
}
