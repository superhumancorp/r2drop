// Packages/R2Core/Sources/R2Core/KeychainManager.swift
// Secure credential storage using macOS Keychain (Security.framework).
// Tokens are stored per-account and shared between main app and Finder extension
// via the App Group access group.
// Tokens are NEVER written to config.toml, logs, or crash reports (FR-005).

import Foundation
import Security

// MARK: - KeychainError

/// Errors from Keychain operations.
public enum KeychainError: Error, Equatable {
    /// Item not found in Keychain.
    case itemNotFound
    /// Item already exists (duplicate insert).
    case duplicateItem
    /// Keychain operation failed with the given OSStatus code.
    case unexpectedError(OSStatus)
}

extension KeychainError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain item not found"
        case .duplicateItem:
            return "Keychain item already exists"
        case .unexpectedError(let status):
            return "Keychain error: \(status)"
        }
    }
}

// MARK: - KeychainManager

/// Manages API token storage in macOS Keychain.
///
/// Uses `Security.framework` directly (SecItemAdd, SecItemCopyMatching,
/// SecItemUpdate, SecItemDelete). Tokens are keyed by account name under
/// the service `com.superhumancorp.r2drop`.
///
/// Access group `group.com.superhumancorp.r2drop` enables the Finder extension
/// to read the same tokens as the main app.
public final class KeychainManager {

    /// The Keychain service identifier.
    private let service: String

    /// The shared access group for main app + Finder extension.
    private let accessGroup: String?

    /// Create a KeychainManager with default service and access group.
    public init() {
        self.service = R2CoreConstants.keychainService
        self.accessGroup = R2CoreConstants.appGroup
    }

    /// Create a KeychainManager with custom service/group (for testing).
    public init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Public API

    /// Store a token for the given account name (FR-002).
    /// Throws `duplicateItem` if a token already exists — use `updateToken` instead.
    public func saveToken(account: String, token: String) throws {
        let tokenData = Data(token.utf8)

        var query = baseQuery(account: account)
        query[kSecValueData as String] = tokenData

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw KeychainError.duplicateItem
        default:
            throw KeychainError.unexpectedError(status)
        }
    }

    /// Retrieve a token for the given account name silently (FR-003).
    /// Returns nil if no token is stored for this account.
    public func getToken(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                return nil
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedError(status)
        }
    }

    /// Delete a token for the given account name.
    /// Throws `itemNotFound` if no token exists for this account.
    public func deleteToken(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedError(status)
        }
    }

    /// Replace an existing token for the given account (FR-008).
    /// Throws `itemNotFound` if no token exists for this account.
    public func updateToken(account: String, token: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8)
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedError(status)
        }
    }

    // MARK: - Private

    /// Build the base Keychain query dictionary for a given account.
    /// Uses kSecClassGenericPassword with the service name as identifier
    /// and the account name as the account attribute.
    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Access group enables sharing between main app and Finder extension.
        // Omitted in tests (nil) so we don't need entitlements.
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}
