// R2Drop/App/Onboarding/OnboardingViewModel.swift
// Shared state and API logic for the onboarding carousel.
// Supports three modes: initial setup, add account, and update token.
// Handles token validation, bucket fetching, account creation/update, and panel navigation.

import SwiftUI
import R2Core
import R2Bridge

// MARK: - Onboarding Mode

/// Determines which panels are shown and how accounts are persisted.
enum OnboardingMode {
    /// Full 5-panel flow on first launch.
    case initial
    /// Panels 3-5 only: create token → paste → choose bucket. Creates a new account.
    case addAccount
    /// Panels 3-5 only: paste new token for an existing account, update Keychain + config.
    case updateToken(String)
}

/// Which panel is currently displayed in the onboarding carousel.
enum OnboardingPanel: Int, CaseIterable {
    case welcome = 0
    case howItWorks = 1
    case createToken = 2
    case pasteToken = 3
    case chooseBucket = 4
}

/// Observable state for all onboarding panels.
/// Views read/write this; the ViewModel drives API calls and persistence.
@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Mode

    /// The mode determines starting panel and save behavior.
    let mode: OnboardingMode

    // MARK: - Navigation

    @Published var currentPanel: OnboardingPanel = .welcome
    @Published var dismissed = false

    // MARK: - Token (Panel 4)

    @Published var tokenText = ""
    @Published var isValidatingToken = false
    @Published var tokenValid = false
    @Published var tokenError: String?

    // Populated after successful validation
    private(set) var accountId = ""
    private(set) var accountName = ""
    private(set) var token = ""

    // MARK: - Bucket (Panel 5)

    @Published var buckets: [String] = []
    @Published var selectedBucket = ""
    @Published var defaultPath = ""
    @Published var customDomain = ""
    @Published var newBucketName = ""
    @Published var isCreatingBucket = false
    @Published var showCreateBucket = false
    @Published var bucketError: String?
    @Published var showCelebration = false

    // MARK: - Dependencies

    private let r2Client = R2Client()
    private let keychainManager = KeychainManager()

    // MARK: - Init

    init(mode: OnboardingMode = .initial) {
        #if DEBUG
        R2Log.ui.debug("OnboardingViewModel: init mode=\(String(describing: mode))")
        #endif
        self.mode = mode

        // Set starting panel based on mode
        switch mode {
        case .initial:
            self.currentPanel = .welcome
        case .addAccount:
            self.currentPanel = .createToken
        case .updateToken(let existingName):
            self.currentPanel = .createToken
            // Pre-populate bucket/path/domain from existing account config
            if let manager = try? AccountManager(),
               let existing = manager.account(named: existingName) {
                self.selectedBucket = existing.bucket
                self.defaultPath = existing.path
                self.customDomain = existing.customDomain ?? ""
            }
        }
    }

    /// The first panel for the current mode (used by navigation guards).
    var firstPanel: OnboardingPanel {
        switch mode {
        case .initial: return .welcome
        case .addAccount, .updateToken: return .createToken
        }
    }

    /// Panels that are visible in this mode (for dot indicators).
    var visiblePanels: [OnboardingPanel] {
        switch mode {
        case .initial:
            return OnboardingPanel.allCases
        case .addAccount, .updateToken:
            return [.createToken, .pasteToken, .chooseBucket]
        }
    }

    // MARK: - Navigation

    /// Move to the next panel.
    func goNext() {
        #if DEBUG
        R2Log.ui.debug("OnboardingViewModel: goNext from \(String(describing: self.currentPanel))")
        #endif
        guard let next = OnboardingPanel(rawValue: currentPanel.rawValue + 1) else { return }
        currentPanel = next
    }

    /// Move to the previous panel. Won't go before the first panel for this mode.
    func goBack() {
        guard currentPanel.rawValue > firstPanel.rawValue,
              let prev = OnboardingPanel(rawValue: currentPanel.rawValue - 1) else { return }
        currentPanel = prev
    }

    /// Skip setup entirely — user can configure later from Accounts tab.
    func skip() {
        dismissed = true
    }

    // MARK: - Token Validation (Panel 4)

    /// Validate the pasted token against Cloudflare API, then fetch accounts.
    /// On success: stores/updates token in Keychain and advances to Panel 5.
    func validateAndStoreToken() async {
        #if DEBUG
        R2Log.ui.debug("OnboardingViewModel: validateAndStoreToken")
        #endif
        let trimmed = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            tokenError = "Please paste your API token."
            return
        }

        isValidatingToken = true
        tokenError = nil
        tokenValid = false

        do {
            // Step 1: Validate token
            try await r2Client.validateToken(trimmed)

            // Step 2: Get account info
            let accounts = try await r2Client.listAccounts(token: trimmed)
            guard let first = accounts.first,
                  let id = first["id"],
                  let name = first["name"] else {
                tokenError = "No Cloudflare accounts found for this token."
                isValidatingToken = false
                return
            }

            self.accountId = id
            self.token = trimmed

            // Step 3: Store in Keychain — behavior depends on mode
            switch mode {
            case .updateToken(let originalName):
                // Keep the original config name; replace the Keychain entry
                self.accountName = originalName
                try keychainManager.updateToken(account: originalName, token: trimmed)
            case .initial, .addAccount:
                // New account — use the CF account name
                self.accountName = name
                do {
                    try keychainManager.saveToken(account: name, token: trimmed)
                } catch KeychainError.duplicateItem {
                    try keychainManager.updateToken(account: name, token: trimmed)
                }
            }

            // Step 4: Fetch buckets for Panel 5
            let bucketList = try await r2Client.listBuckets(accountId: id, token: trimmed)
            self.buckets = bucketList
            // Only auto-select first bucket if no bucket is pre-selected
            if selectedBucket.isEmpty, let first = bucketList.first {
                self.selectedBucket = first
            }

            tokenValid = true
        #if DEBUG
        R2Log.ui.debug("OnboardingViewModel: token valid, accountId=\(self.accountId)")
        #endif
            isValidatingToken = false

            // Clear plaintext token from text field (FR-005)
            tokenText = ""

            // Advance to bucket selection
            goNext()

        } catch {
            #if DEBUG
            R2Log.ui.error("OnboardingViewModel: validateToken failed: \(error)")
            #endif
            tokenError = "This token doesn't appear to be valid. Please check that you copied the full token."
            isValidatingToken = false
        }
    }

    /// Clear token field and error state for retry.
    func clearToken() {
        tokenText = ""
        tokenError = nil
        tokenValid = false
    }

    // MARK: - Bucket Operations (Panel 5)

    /// Create a new bucket, then refresh the bucket list.
    func createNewBucket() async {
        let name = newBucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            bucketError = "Bucket name cannot be empty."
            return
        }

        isCreatingBucket = true
        bucketError = nil

        do {
            try await r2Client.createBucket(accountId: accountId, name: name, token: token)
            let updated = try await r2Client.listBuckets(accountId: accountId, token: token)
            buckets = updated
            selectedBucket = name
            newBucketName = ""
            showCreateBucket = false
            isCreatingBucket = false
        } catch {
            bucketError = "Failed to create bucket: \(error.localizedDescription)"
            isCreatingBucket = false
        }
    }

    /// Finish onboarding: persist account to config.toml and dismiss.
    func finishSetup() async {
        #if DEBUG
        R2Log.ui.debug("OnboardingViewModel: finishSetup account=\(self.accountName) bucket=\(self.selectedBucket)")
        #endif
        let account = ConfigAccount(
            name: accountName,
            bucket: selectedBucket,
            path: defaultPath,
            customDomain: customDomain.isEmpty ? nil : customDomain,
            accountId: accountId
        )

        do {
            let manager = try AccountManager()
            switch mode {
            case .updateToken:
                // Update existing account config (bucket, path, domain may have changed)
                try manager.updateAccount(account)
            case .initial, .addAccount:
                // Add as new account
                try manager.addAccount(account)
            }
        } catch {
            // Best-effort — account may already exist from re-onboarding
        }

        // FR-005: Wipe plaintext token from memory now that it's in Keychain
        token = ""

        // Show celebration briefly, then dismiss
        showCelebration = true
        try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 seconds
        dismissed = true
    }
}
