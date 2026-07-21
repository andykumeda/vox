import Foundation
import Security

public enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case dataEncodingFailed
}

public struct KeychainStore: Sendable {
    public let service: String
    public let account: String

    public init(service: String = "com.andykumeda.vox", account: String = "openai-api-key") {
        self.service = service
        self.account = account
    }

    public func save(_ value: String) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let data = value.data(using: .utf8) else { throw KeychainError.dataEncodingFailed }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            // A cached value may have been removed by another process. Do not
            // return it if creating the replacement item fails.
            Self.cache.removeValue(forKey: cacheKey)
            var addQuery = baseQuery
            addQuery.merge(attributes) { _, replacement in replacement }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            // Updating in place preserves the existing credential and cache if
            // Security.framework rejects the replacement.
            throw KeychainError.unexpectedStatus(updateStatus)
        }
        Self.cache[cacheKey] = value
    }

    public func read() -> String? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let cached = Self.cache[cacheKey] { return cached }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        Self.cache[cacheKey] = value
        return value
    }

    /// Process-lifetime cache so we don't trigger a Keychain ACL prompt on every
    /// dictation/meeting transcribe call (transcriber + cleaner each call read()).
    /// Invalidated by `save()` and `delete()`. Security.framework calls and cache
    /// mutations share one lock so startup warmup cannot race Settings or STT.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    private var cacheKey: String { "\(service)|\(account)" }

    public func delete() throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
        Self.cache.removeValue(forKey: cacheKey)
    }
}
