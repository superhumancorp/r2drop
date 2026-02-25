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

                let isValid = await validateSingleToken(token)
                if !isValid {
                    invalidAccounts.append(account.name)
                    #if DEBUG
                    R2Log.service.debug("TokenValidationService: token invalid for account \(account.name)")
                    #endif
                    postTokenExpiredNotification(accountName: account.name)
                } else {
                    #if DEBUG
                    R2Log.service.debug("TokenValidationService: token valid for account \(account.name)")
                    #endif
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
    /// Returns true if the token is still valid.
    private func validateSingleToken(_ token: String) async -> Bool {
        do {
            try await r2Client.validateToken(token)
            return true
        } catch {
            return false
        }
    }

    /// Load all configured accounts from config.toml.
    private func loadAccounts() -> [ConfigAccount] {
        do {
            let config = try ConfigManager.load()
            // Deduplicate by name to avoid validating the same account multiple times
            var seen = Set<String>()
            return config.accounts.filter { account in
                guard !seen.contains(account.name) else { return false }
                seen.insert(account.name)
                return true
            }
        } catch {
            return []
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
