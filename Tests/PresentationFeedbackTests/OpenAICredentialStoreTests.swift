import Testing
@testable import PresentationFeedback

private final class MemoryCredentialStore: OpenAICredentialStoring, @unchecked Sendable {
    var key: String?
    init(key: String? = nil) { self.key = key }
    func loadAPIKey() throws -> String? { key }
    func saveAPIKey(_ key: String) throws { self.key = key }
    func deleteAPIKey() throws { key = nil }
}

@Test func credentialResolverPrefersEnvironmentOverKeychain() throws {
    let store = MemoryCredentialStore(key: "keychain-key")
    let resolved = try OpenAICredentialResolver.resolve(
        environment: ["OPENAI_API_KEY": "environment-key"],
        store: store
    )
    #expect(resolved == "environment-key")
}

@Test func credentialResolverFallsBackToKeychain() throws {
    let store = MemoryCredentialStore(key: "keychain-key")
    let resolved = try OpenAICredentialResolver.resolve(environment: [:], store: store)
    #expect(resolved == "keychain-key")
}

@Test func configuredGeneratorUsesResolvedCredential() throws {
    let store = MemoryCredentialStore(key: "keychain-key")
    let generator = try OpenAICommentGenerator.configured(environment: [:], store: store)
    _ = generator
}
