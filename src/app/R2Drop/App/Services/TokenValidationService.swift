// R2Drop/App/Services/TokenValidationService.swift
// Background service that validates API tokens on launch and periodically (every 24h).
// Posts macOS notifications when a token is revoked or expired (FR-004).
// Retrieves tokens silently from Keychain on launch (FR-003).

import Foundation
import R2Core
import R2Bridge

// MARK: - TokenValidationService

/// Validates all stored API tokens on app launch and every 24 hours.
/// Posts a notification if any token is revoked, prompting re-setup.
@MainActor
final class TokenValidationService: ObservableObject {

    /// Whether a token validation check is currently running.
    @Published var isChecking = false

    /// Account names whose tokens have been found invalid.
    @Published var invalidAccounts: [String] = []

    // MARK: - Dependencies

    private let r2Client = R2Client()
    private let keychainManager = KeychainManager()

    /// Timer task for periodic re-validation.
    private var periodicTask: Task<Void, Never>?

    /// 24 hours in seconds.
    private static let validationInterval: TimeInterval = 24 * 60 * 60

    // MARK: - Lifecycle

    /// Start the service: validate immediately, then schedule periodic checks.
    func start() {
        #if DEBUG
        R2Log.service.debug("TokenValidationService: start")
        #endif
        validateAllTokens()
        schedulePeriodicValidation()
    }

    /// Stop the service and cancel the periodic timer.
    func stop() {
        #if DEBUG
        R2Log.service.debug("TokenValidationService: stop")
        #endif
        periodicTask?.cancel()
        periodicTask = nil
    }

    deinit {
        periodicTask?.cancel()
    }

    // MARK: - Validation

    /// Validate tokens for all configured accounts.
    /// Runs asynchronously in the background.
    func validateAllTokens() {
        #if DEBUG
        R2Log.service.debug("TokenValidationService: validateAllTokens begin")
        #endif
        Task { @MainActor in
            isChecking = true
            invalidAccounts = []

            let accounts = loadAccounts()

            for account in accounts {
                // FR-003: Retrieve token silently from Keychain
                guard let token = try? keychainManager.getToken(account: account.name) else {
                    continue
                }

                if let tokenId = await validateSingleToken(token) {
                    backfillTokenIdIfNeeded(accountName: account.name, tokenId: tokenId)
                    #if DEBUG
                    R2Log.service.debug("TokenValidationService: token valid for account \(account.name)")
                    #endif
                } else {
                    invalidAccounts.append(account.name)
                    #if DEBUG
                    R2Log.service.debug("TokenValidationService: token invalid for account \(account.name)")
                    #endif
                    postTokenExpiredNotification(accountName: account.name)
                }
            }

            isChecking = false
            #if DEBUG
            R2Log.service.debug("TokenValidationService: validateAllTokens end")
            #endif
        }
    }

    // MARK: - Private

    /// Validate a single token against the Cloudflare API.
    /// Returns the token UUID (S3 access key ID) if valid.
    private func validateSingleToken(_ token: String) async -> String? {
        do {
            return try await r2Client.validateToken(token)
        } catch {
            return nil
        }
    }

    /// Load all configured accounts from config.toml.
    private func loadAccounts() -> [ConfigAccount] {
        do {
            let config = try ConfigManager.load()
            // Deduplicate by name and accountId to avoid validating the same account multiple times
            var seenNames = Set<String>()
            var seenAccountIds = Set<String>()
            return config.accounts.filter { account in
                guard !seenNames.contains(account.name) else { return false }
                if !account.accountId.isEmpty {
                    guard !seenAccountIds.contains(account.accountId) else { return false }
                    seenAccountIds.insert(account.accountId)
                }
                seenNames.insert(account.name)
                return true
            }
        } catch {
            return []
        }
    }

    /// Backfill legacy accounts missing tokenId so uploads continue to work.
    /// Best-effort; validation should not fail just because config persistence fails.
    private func backfillTokenIdIfNeeded(accountName: String, tokenId: String) {
        guard !tokenId.isEmpty else { return }
        do {
            var config = try ConfigManager.load()
            guard let idx = config.accounts.firstIndex(where: { $0.name == accountName }) else { return }
            guard config.accounts[idx].tokenId != tokenId else { return }
            config.accounts[idx].tokenId = tokenId
            try ConfigManager.save(config)
            #if DEBUG
            R2Log.service.debug("TokenValidationService: backfilled tokenId for account \(accountName)")
            #endif
        } catch {
            #if DEBUG
            R2Log.service.error("TokenValidationService: failed to backfill tokenId for \(accountName): \(error)")
            #endif
        }
    }

    /// Schedule periodic token re-validation every 24 hours (FR-004).
    private func schedulePeriodicValidation() {
        periodicTask?.cancel()
        periodicTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.validationInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                self?.validateAllTokens()
            }
        }
    }

    // MARK: - Notifications

    /// Delegate token expired notifications to the centralized NotificationService (FR-062).
    private func postTokenExpiredNotification(accountName: String) {
        NotificationService.shared.notifyTokenExpired(accountName: accountName)
    }
}
