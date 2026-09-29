import Foundation
import Security

/// The key that unlocked Pro, kept so Pro survives restarts without asking the store again.
public struct StoredLicense: Codable, Equatable, Sendable {
    public var key: String
    public var checkedAt: Date

    public init(key: String, checkedAt: Date) {
        self.key = key
        self.checkedAt = checkedAt
    }
}

public protocol LicenseCache: Sendable {
    func load() -> StoredLicense?
    func save(_ license: StoredLicense) throws
    func clear()
}

/// One generic-password item in the login Keychain.
public struct KeychainLicenseCache: LicenseCache {
    public enum Failure: Error, Equatable { case status(OSStatus) }

    let service: String
    let account = "license"

    public init(service: String = "dev.opusbar.OpusBar.license") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> StoredLicense? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredLicense.self, from: data)
    }

    public func save(_ license: StoredLicense) throws {
        let data = try JSONEncoder().encode(license)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure.status(added) }
        } else if status != errSecSuccess {
            throw Failure.status(status)
        }
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
