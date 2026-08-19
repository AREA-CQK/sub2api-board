import Foundation
import Security

enum KeychainStore {
    private static let account = "auth.tokens"

    static func save(_ tokens: AuthTokens) throws {
        let data = try JSONEncoder.sub2api.encode(tokens)
        try upsert(data, query: baseQuery)
    }

    static func load() throws -> AuthTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw APIError.keychain(status) }
        return try JSONDecoder.sub2api.decode(AuthTokens.self, from: data)
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static func saveSharedData(_ data: Data, account: String) throws {
        try upsert(data, query: sharedDataQuery(account: account))
    }

    static func loadSharedData(account: String) throws -> Data? {
        var query = sharedDataQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw APIError.keychain(status)
        }
        return data
    }

    static func clearSharedData(account: String) {
        SecItemDelete(sharedDataQuery(account: account) as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        query(
            service: AppConfiguration.keychainService,
            account: account
        )
    }

    private static func sharedDataQuery(account: String) -> [String: Any] {
        query(
            service: AppConfiguration.sharedStoreKeychainService,
            account: account
        )
    }

    private static func query(service: String, account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let group = AppConfiguration.keychainAccessGroup, !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    private static func upsert(_ data: Data, query: [String: Any]) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw APIError.keychain(updateStatus) }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { return }

        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard retryStatus == errSecSuccess else { throw APIError.keychain(retryStatus) }
            return
        }
        throw APIError.keychain(addStatus)
    }
}
