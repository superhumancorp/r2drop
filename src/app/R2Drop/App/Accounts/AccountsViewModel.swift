// R2Drop/App/Accounts/AccountsViewModel.swift
// ViewModel for the Accounts tab in Preferences (US-018, FR-041 through FR-044).
// Loads accounts from config.toml, manages selection, handles edits,
// and delegates to AppDelegate for add/update-token/log-out flows.

import SwiftUI
import R2Core
import R2Bridge

@MainActor
final class AccountsViewModel: ObservableObject {

    // MARK: - Published State

    /// All configured accounts, loaded from config.toml.
    @Published var accounts: [ConfigAccount] = []

    /// Currently selected account name in the sidebar.
    @Published var selectedAccountName: String?

    /// Editable fields for the selected account detail panel (FR-043).
    @Published var editName: String = ""
    @Published var editBucket: String = ""
    @Published var editPath: String = ""
    @Published var editCustomDomain: String = ""

    /// Bucket dropdown data (fetched from Cloudflare API).
    @Published var availableBuckets: [String] = []
    @Published var isLoadingBuckets = false
    @Published var bucketError: String?

    /// Path validation: must not contain leading slash or double slashes.
    @Published var pathError: String?

    /// True when there are unsaved edits on the detail panel.
    @Published var hasUnsavedChanges = false

    // MARK: - Dependencies

    private let r2Client = R2Client()
    private let keychainManager = KeychainManager()

    // MARK: - Load

    /// Reload accounts from config.toml and select the first if none selected.
    func load() {
        #if DEBUG
        R2Log.ui.debug("AccountsViewModel: load")
        #endif
        let config = (try? ConfigManager.load()) ?? R2Config()
        accounts = config.accounts

        // If the selected account was removed, clear selection
        if let name = selectedAccountName,
           !accounts.contains(where: { $0.name == name }) {
            selectedAccountName = nil
        }

        // Auto-select first account if nothing is selected
        if selectedAccountName == nil, let first = accounts.first {
            selectAccount(first.name)
        }
    }

    // MARK: - Selection

    /// Select an account by name and populate the detail fields.
    func selectAccount(_ name: String) {
        #if DEBUG
        R2Log.ui.debug("AccountsViewModel: selectAccount \(name)")
        #endif
        guard let account = accounts.first(where: { $0.name == name }) else { return }
        selectedAccountName = name
        editName = account.name
        editBucket = account.bucket
        editPath = account.path
        editCustomDomain = account.customDomain ?? ""
        pathError = nil
        hasUnsavedChanges = false
        bucketError = nil

        // Fetch buckets for the dropdown
        fetchBuckets(for: account)
    }

    /// The currently selected account object.
    var selectedAccount: ConfigAccount? {
        guard let name = selectedAccountName else { return nil }
        return accounts.first { $0.name == name }
    }

    // MARK: - Fetch Buckets

    /// Fetch bucket list from Cloudflare API for the selected account.
    private func fetchBuckets(for account: ConfigAccount) {
        guard !account.accountId.isEmpty else {
            availableBuckets = account.bucket.isEmpty ? [] : [account.bucket]
            return
        }

        isLoadingBuckets = true
        bucketError = nil

        Task {
            do {
                guard let token = try keychainManager.getToken(account: account.name) else {
                    bucketError = "No token found in Keychain."
                    isLoadingBuckets = false
                    return
                }
                let buckets = try await r2Client.listBuckets(
                    accountId: account.accountId, token: token
                )
                availableBuckets = buckets
                isLoadingBuckets = false
            } catch {
                bucketError = "Could not load buckets."
                // Show the current bucket at minimum
                availableBuckets = account.bucket.isEmpty ? [] : [account.bucket]
                isLoadingBuckets = false
            }
        }
    }

    // MARK: - Validation

    /// Validate the default path field. Returns true if valid.
    func validatePath() -> Bool {
        let path = editPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/") {
            pathError = "Path should not start with '/'"
            return false
        }
        if path.contains("//") {
            pathError = "Path should not contain '//'"
            return false
        }
        pathError = nil
        return true
    }

    /// Called whenever an edit field changes. Marks unsaved state.
    func markEdited() {
        guard let account = selectedAccount else { return }
        hasUnsavedChanges = (
            editName != account.name ||
            editBucket != account.bucket ||
            editPath != account.path ||
            editCustomDomain != (account.customDomain ?? "")
        )
    }

    // MARK: - Save Changes (FR-043)

    /// Persist edits to config.toml for the selected account.
    func saveChanges() {
        guard let originalName = selectedAccountName else { return }
        #if DEBUG
        R2Log.ui.debug("AccountsViewModel: saveChanges for \(originalName)")
        #endif
        guard validatePath() else { return }

        let updated = ConfigAccount(
            name: editName.trimmingCharacters(in: .whitespacesAndNewlines),
            bucket: editBucket,
            path: editPath.trimmingCharacters(in: .whitespacesAndNewlines),
            customDomain: editCustomDomain.isEmpty ? nil : editCustomDomain.trimmingCharacters(in: .whitespacesAndNewlines),
            accountId: selectedAccount?.accountId ?? ""
        )

        do {
            let manager = try AccountManager()
            try manager.updateAccount(updated)
            hasUnsavedChanges = false
            // Refresh list from disk
            load()
            // Re-select to update detail view
            selectAccount(updated.name)
        } catch {
            // Best-effort save
        }
    }

    // MARK: - Actions (FR-044)

    /// Trigger the "Add Account" flow via AppDelegate (FR-042).
    func addAccount() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.showAddAccount()
    }

    /// Trigger the "Update Token" flow via AppDelegate (FR-044).
    func updateToken(accountName: String) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.showUpdateToken(accountName: accountName)
    }

    /// Trigger the "Log Out" flow via AppDelegate with confirmation (FR-044).
    func logOut(accountName: String) {
        #if DEBUG
        R2Log.ui.debug("AccountsViewModel: logOut \(accountName)")
        #endif
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.logOut(accountName: accountName)
        // Refresh after log out
        load()
    }
}
