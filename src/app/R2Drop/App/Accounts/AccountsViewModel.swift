// R2Drop/App/Accounts/AccountsViewModel.swift
// ViewModel for the Accounts tab in Preferences (US-018, FR-041 through FR-044).
// Loads accounts from config.toml, manages selection, handles edits,
// and delegates to AppDelegate for add/update-token/log-out flows.

import SwiftUI
import R2Core
import R2Bridge

@MainActor
final class AccountsViewModel: ObservableObject {

    /// Observer for account change notifications (from onboarding, add account, etc.)
    private var accountChangeObserver: NSObjectProtocol?

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

    /// Custom domains fetched from Cloudflare API for the selected account.
    @Published var customDomains: [String] = []
    @Published var isLoadingDomains = false

    /// Visual feedback for account ID copy button.
    @Published var copiedAccountId = false

    // MARK: - Dependencies

    private let r2Client = R2Client()
    private let keychainManager = KeychainManager()

    // MARK: - Init / Deinit

    init() {
        // Listen for account changes from onboarding/add-account flows
        accountChangeObserver = NotificationCenter.default.addObserver(
            forName: .r2dropAccountsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.load()
            }
        }
    }

    deinit {
        if let observer = accountChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
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

        // Fetch custom domains for the dropdown
        fetchCustomDomains(for: account)
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

    // MARK: - Fetch Custom Domains

    /// Fetch custom domains from Cloudflare API for the selected account.
    /// Cached locally; refreshed on explicit user action.
    private func fetchCustomDomains(for account: ConfigAccount) {
        guard !account.accountId.isEmpty, !account.bucket.isEmpty else { return }
        isLoadingDomains = true
        customDomains = []  // Clear stale data

        Task {
            guard let token = try? keychainManager.getToken(account: account.name) else {
                isLoadingDomains = false
                return
            }
            guard let encodedBucket = account.bucket.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                isLoadingDomains = false
                return
            }
            let urlString = "https://api.cloudflare.com/client/v4/accounts/\(account.accountId)/r2/buckets/\(encodedBucket)/domains/custom"
            guard let url = URL(string: urlString) else {
                isLoadingDomains = false
                return
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
                if httpStatus == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] as? [String: Any],
                   let domainEntries = result["domains"] as? [[String: Any]] {
                    let activeDomains = domainEntries.compactMap { entry -> String? in
                        guard let domain = entry["domain"] as? String,
                              let enabled = entry["enabled"] as? Bool, enabled else {
                            return nil
                        }
                        if let status = entry["status"] as? [String: Any],
                           let ownership = status["ownership"] as? String,
                           ownership == "deactivated" { return nil }
                        return domain
                    }
                    self.customDomains = activeDomains
                }
            } catch {
                // Non-fatal — custom domains are optional
            }
            isLoadingDomains = false
        }
    }

    /// Refresh custom domains for the currently selected account.
    func refreshDomains() {
        guard let account = selectedAccount else { return }
        fetchCustomDomains(for: account)
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
            bucket: editBucket.trimmingCharacters(in: .whitespacesAndNewlines),
            path: editPath.trimmingCharacters(in: .whitespacesAndNewlines),
            customDomain: editCustomDomain.isEmpty ? nil : editCustomDomain.trimmingCharacters(in: .whitespacesAndNewlines),
            accountId: selectedAccount?.accountId ?? "",
            tokenId: selectedAccount?.tokenId ?? ""
        )

        // P0: account_edit_save_started
        let renamed = editName != originalName
        let bucketChanged = editBucket != (selectedAccount?.bucket ?? "")
        let pathChanged = editPath != (selectedAccount?.path ?? "")
        let customDomainChanged = editCustomDomain != (selectedAccount?.customDomain ?? "")
        TelemetryService.shared.track("account_edit_save_started", properties: [
            "renamed": renamed,
            "bucket_changed": bucketChanged,
            "path_changed": pathChanged,
            "custom_domain_changed": customDomainChanged
        ])

        do {
            let manager = try AccountManager()
            let didUpdate = try manager.updateAccount(named: originalName, to: updated)
            guard didUpdate else {
                #if DEBUG
                R2Log.ui.error("AccountsViewModel: saveChanges failed \u{2014} original account '\(originalName)' not found")
                #endif
                // P0: account_edit_save_failed
                TelemetryService.shared.track("account_edit_save_failed", properties: [
                    "reason": "account_not_found"
                ])
                return
            }
            hasUnsavedChanges = false
            // P0: account_edit_save_succeeded
            TelemetryService.shared.track("account_edit_save_succeeded", properties: [
                "renamed": renamed,
                "has_custom_domain": !editCustomDomain.isEmpty
            ])
            // Refresh list from disk
            load()
            // Re-select to update detail view
            selectAccount(updated.name)
        } catch {
            #if DEBUG
            R2Log.ui.error("AccountsViewModel: saveChanges error: \(error)")
            #endif
            // P0: account_edit_save_failed
            TelemetryService.shared.track("account_edit_save_failed", properties: [
                "reason": String(describing: error)
            ])
        }
    }
    // MARK: - Actions (FR-044)

    /// Trigger the "Add Account" flow via AppDelegate (FR-042).
    func addAccount() {
        guard let appDelegate = AppDelegate.shared else { return }
        appDelegate.showAddAccount()
    }

    /// Trigger the "Update Token" flow via AppDelegate (FR-044).
    func updateToken(accountName: String) {
        guard let appDelegate = AppDelegate.shared else { return }
        appDelegate.showUpdateToken(accountName: accountName)
    }

    /// Trigger the "Log Out" flow via AppDelegate with confirmation (FR-044).
    func logOut(accountName: String) {
        #if DEBUG
        R2Log.ui.debug("AccountsViewModel: logOut \(accountName)")
        #endif
        guard let appDelegate = AppDelegate.shared else { return }
        appDelegate.logOut(accountName: accountName)
        // Refresh after log out
        load()
    }

    // MARK: - Deduplication

    /// Remove duplicate accounts by name, keeping the first occurrence.
    /// Handles legacy config files that accumulated duplicates.
    private func deduplicateAccounts(_ accounts: [ConfigAccount]) -> [ConfigAccount] {
        var seen = Set<String>()
        return accounts.filter { account in
            guard !seen.contains(account.name) else { return false }
            seen.insert(account.name)
            return true
        }
    }
}
