// Packages/R2Core/Sources/R2Core/AccountManager.swift
// Multi-account CRUD operations for Cloudflare R2 accounts.
// Persists changes to ~/.r2drop/config.toml via ConfigManager.
// Provides active account switching and account lookup.

import Foundation

// MARK: - AccountManager

/// Manages multiple Cloudflare R2 accounts.
/// Each account has a display name, bucket, default upload path, and optional custom domain.
/// Credentials (API tokens) are stored separately in macOS Keychain, not in config.
public final class AccountManager {
    private var config: R2Config
    private let configPath: URL?

    /// Create a manager backed by the default config file.
    public init() throws {
        self.configPath = nil
        self.config = try ConfigManager.load()
    }

    /// Create a manager backed by a specific config file (for testing).
    public init(configPath: URL) throws {
        self.configPath = configPath
        self.config = try ConfigManager.load(from: configPath)
    }

    // MARK: - Read

    /// All configured accounts.
    public var accounts: [ConfigAccount] { config.accounts }

    /// The currently active account name.
    public var activeAccountName: String? { config.activeAccount }

    /// The currently active account, if any.
    public var activeAccount: ConfigAccount? {
        guard let name = config.activeAccount else { return nil }
        return config.accounts.first { $0.name == name }
    }

    /// Look up an account by name.
    public func account(named name: String) -> ConfigAccount? {
        config.accounts.first { $0.name == name }
    }

    // MARK: - Write

    /// Add a new account. If an account with the same name already exists,
    /// updates it instead of creating a duplicate. Sets as active if it's the first.
    public func addAccount(_ account: ConfigAccount) throws {
        if let idx = config.accounts.firstIndex(where: { $0.name == account.name }) {
            // Account already exists — update instead of duplicating
            config.accounts[idx] = account
        } else {
            config.accounts.append(account)
        }
        // Set as active if it's the only account
        if config.accounts.count == 1 || config.activeAccount == nil {
            config.activeAccount = account.name
        }
        try save()
    }

    /// Update an existing account (matched by name).
    public func updateAccount(_ account: ConfigAccount) throws {
        guard let idx = config.accounts.firstIndex(where: { $0.name == account.name }) else {
            return
        }
        config.accounts[idx] = account
        try save()
    }

    /// Remove an account by name.
    /// If the removed account was active, switches to the first remaining account.
    public func removeAccount(named name: String) throws {
        config.accounts.removeAll { $0.name == name }
        if config.activeAccount == name {
            config.activeAccount = config.accounts.first?.name
        }
        try save()
    }

    /// Switch the active account to the one with the given name.
    /// Returns false if no account with that name exists.
    @discardableResult
    public func switchAccount(to name: String) throws -> Bool {
        guard config.accounts.contains(where: { $0.name == name }) else {
            return false
        }
        config.activeAccount = name
        try save()
        return true
    }

    /// Reload config from disk (picks up changes from Rust engine or CLI).
    public func reload() throws {
        config = try ConfigManager.load(from: configPath)
    }

    // MARK: - Private

    private func save() throws {
        try ConfigManager.save(config, to: configPath)
    }
}
