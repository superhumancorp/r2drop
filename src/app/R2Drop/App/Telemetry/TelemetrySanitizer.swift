// R2Drop/App/Telemetry/TelemetrySanitizer.swift
// Sanitizes sensitive values before sending to PostHog.
// Uses SHA256(install_salt + ":" + value) for consistent per-install hashing.
// The install salt is a random UUID generated once and stored in Keychain.
// Provides helpers for file extension extraction, path depth, and size bucketing.

import Foundation
import CryptoKit
import Security

// MARK: - TelemetrySanitizer

/// Sanitizes sensitive data before it leaves the device.
/// All hashing uses a per-install salt so values are consistent within
/// an install but cannot be reversed or correlated across installs.
enum TelemetrySanitizer {

    // MARK: - Keychain Constants

    private static let keychainService = "com.superhumancorp.r2drop.analytics"
    private static let saltAccount = "install_salt"

    // MARK: - Salt (lazy, thread-safe via static let)

    /// Per-install salt used for all hashing. Generated once, persisted in Keychain.
    /// Falls back to a transient UUID if Keychain is unavailable (should never happen).
    private static let installSalt: String = {
        if let existing = readKeychain(account: saltAccount) {
            return existing
        }
        let newSalt = UUID().uuidString.lowercased()
        saveKeychain(account: saltAccount, value: newSalt)
        return newSalt
    }()

    // MARK: - Public API

    /// Hash a sensitive string (account name, bucket name, custom domain, etc.)
    /// Returns a stable 12-character hex prefix of SHA256(salt + ":" + value).
    /// Short prefix keeps payloads compact while still being unique enough for grouping.
    static func hash(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        let input = "\(installSalt):\(value)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// Extract just the file extension from a path or filename.
    /// Returns lowercased extension without the dot, or "none" if no extension.
    static func fileExtension(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "none" : ext
    }

    /// Count the depth (number of path components) of a path string.
    /// e.g. "photos/2024/jan/img.jpg" → 4
    static func pathDepth(_ path: String) -> Int {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: "/").count
    }

    /// Bucket a byte size into a human-readable range for analytics grouping.
    /// Avoids sending exact file sizes which could identify specific files.
    static func sizeBucket(_ bytes: UInt64) -> String {
        switch bytes {
        case 0:                         return "0"
        case 1..<1_024:                 return "<1KB"
        case 1_024..<102_400:           return "1KB-100KB"
        case 102_400..<1_048_576:       return "100KB-1MB"
        case 1_048_576..<10_485_760:    return "1MB-10MB"
        case 10_485_760..<104_857_600:  return "10MB-100MB"
        case 104_857_600..<1_073_741_824: return "100MB-1GB"
        default:                        return ">1GB"
        }
    }

    /// Hash an error message so we can group errors without leaking paths/tokens.
    static func errorHash(_ message: String) -> String {
        hash(message)
    }

    // MARK: - Keychain Helpers

    /// Read a string value from the analytics Keychain service.
    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Save a string value to the analytics Keychain service.
    private static func saveKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        // Delete existing entry first (idempotent)
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
