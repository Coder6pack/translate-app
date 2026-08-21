import Foundation
import Security

struct KeychainStore: Sendable {
    private let service: String
    private let account = "google-cloud-translation-api-key"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.coder6pack.TranslateApp") {
        self.service = service
    }

    func apiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveAPIKey(_ newAPIKey: String) throws {
        let trimmedKey = newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmedKey.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status: OSStatus
        if apiKey() == nil {
            var item = identity
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        } else {
            status = SecItemUpdate(
                identity as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func removeAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case encodingFailed
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "The API key could not be encoded."
        case .status(let status):
            SecCopyErrorMessageString(status, nil) as String?
        }
    }
}
