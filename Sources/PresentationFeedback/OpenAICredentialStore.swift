import Foundation
import Security

public protocol OpenAICredentialStoring: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

public enum OpenAICredentialStoreError: Error, LocalizedError, Equatable {
    case invalidKey
    case keychainStatus(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidKey: "APIキーが空です。"
        case let .keychainStatus(status):
            if let message = SecCopyErrorMessageString(OSStatus(status), nil) as String? {
                "Keychainエラー: \(message)"
            } else {
                "Keychainエラー: \(status)"
            }
        }
    }
}

public struct KeychainOpenAICredentialStore: OpenAICredentialStoring, Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.mocorocket.presentation-coach.openai",
        account: String = "OPENAI_API_KEY"
    ) {
        self.service = service
        self.account = account
    }

    public func loadAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw OpenAICredentialStoreError.keychainStatus(status)
        }
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    public func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenAICredentialStoreError.invalidKey }
        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw OpenAICredentialStoreError.keychainStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw OpenAICredentialStoreError.keychainStatus(updateStatus)
        }
    }

    public func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAICredentialStoreError.keychainStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public enum OpenAICredentialResolver {
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: any OpenAICredentialStoring = KeychainOpenAICredentialStore()
    ) throws -> String? {
        if let environmentKey = environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !environmentKey.isEmpty {
            return environmentKey
        }
        return try store.loadAPIKey()
    }
}
