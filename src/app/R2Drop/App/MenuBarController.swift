// R2Drop/App/MenuBarController.swift
// Manages the NSStatusItem in the macOS menu bar.
// Handles: persistent icon (FR-034), pulsing animation during uploads (FR-035),
// dropdown menu with toggle/accounts/queue/prefs/quit (FR-036),
// and drag-and-drop file uploads (FR-066).
// Uses a custom template image from the asset catalog for light/dark adaptation.

import AppKit
import R2Bridge
import R2Core

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var animationTimer: Timer?
    private var uploadCheckTimer: Timer?
    private var animationFrame = 0
    private(set) var isUploading = false

    /// Master on/off toggle — when off, new uploads are paused.
    var isEnabled: Bool = true {
        didSet { updateIcon() }
    }

    // MARK: - Icons (custom asset, template = light/dark auto)

    /// Load the custom menu bar icon from the asset catalog.
    /// Marked as template so macOS auto-tints for light/dark menu bar.
    private static let menuBarIcon: NSImage? = {
        let img = NSImage(named: "MenuBarIcon")
        img?.isTemplate = true
        return img
    }()

    // MARK: - Init

    override init() {
        super.init()
        setupStatusItem()
        startUploadCheck()
    }

    deinit {
        animationTimer?.invalidate()
        uploadCheckTimer?.invalidate()
    }

    // MARK: - Status Item Setup (FR-034)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        // Dropdown menu
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Drag-and-drop overlay (FR-066)
        setupDragDrop()
    }

    // MARK: - Icon & Animation (FR-035)

    /// Set the status item icon based on current state.
    /// Uses the custom MenuBarIcon asset — alpha dimmed when disabled.
    func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = Self.menuBarIcon
        if !isEnabled {
            button.alphaValue = 0.4
            stopAnimation()
            return
        }
        button.alphaValue = 1.0
        if isUploading {
            startAnimation()
        } else {
            stopAnimation()
        }
    }

    /// Start pulsing between filled and outline icons.
    /// Respects macOS "Reduce motion" accessibility setting — when enabled,
    /// shows a static uploading icon instead of animating.
    private func startAnimation() {
        guard animationTimer == nil else { return }

        // If user has "Reduce motion" enabled, show static uploading icon only
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            statusItem.button?.alphaValue = 1.0
            return
        }

        animationFrame = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.animateIcon() }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    /// Alternate between filled and outline icons for a pulse effect.
    /// Also re-checks reduced motion on each frame — if the user toggles
    /// "Reduce motion" mid-animation, we stop gracefully.
    private func animateIcon() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            stopAnimation()
            statusItem.button?.alphaValue = 1.0
            return
        }
        guard let button = statusItem.button else { return }
        animationFrame = (animationFrame + 1) % 2
        // Pulse between full and half opacity to indicate active upload
        button.alphaValue = animationFrame == 0 ? 1.0 : 0.5
    }

    // MARK: - Upload State Polling

    /// Polls queue.db every 2 seconds to check for active uploads.
    /// Drives icon animation on/off.
    private func startUploadCheck() {
        uploadCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkUploadState() }
        }
    }

    private func checkUploadState() {
        let wasUploading = isUploading
        isUploading = hasActiveUploads()
        if wasUploading != isUploading { updateIcon() }
    }

    private func hasActiveUploads() -> Bool {
        guard let qm = try? QueueManager() else { return false }
        let jobs = (try? qm.listJobs(status: .uploading)) ?? []
        return !jobs.isEmpty
    }

    // MARK: - NSMenuDelegate

    /// Rebuild the menu each time it opens for fresh data.
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    // MARK: - Menu Construction (FR-036)

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. On/Off toggle
        let toggleTitle = isEnabled ? "R2Drop is On" : "R2Drop is Off"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = isEnabled ? .on : .off
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        // 2. Account section
        let config = (try? ConfigManager.load()) ?? R2Config()
        if !config.accounts.isEmpty {
            addAccountItems(to: menu, accounts: config.accounts, active: config.activeAccount)
            menu.addItem(.separator())
        }

        // Add Account
        let addItem = NSMenuItem(title: "Add Account...", action: #selector(addAccount), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)
        menu.addItem(.separator())

        // 3. Queue summary (only shown when there are jobs)
        addQueueSummary(to: menu)

        // 4. Preferences
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(.separator())

        // 5. Quit
        let quitItem = NSMenuItem(title: "Quit R2Drop", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Add per-account submenu items with Set Active / Update Token / Log Out.
    private func addAccountItems(to menu: NSMenu, accounts: [ConfigAccount], active: String?) {
        for account in accounts {
            let submenu = NSMenu()

            if account.name != active {
                let setActive = NSMenuItem(title: "Set Active", action: #selector(setActiveAccount(_:)), keyEquivalent: "")
                setActive.target = self
                setActive.representedObject = account.name
                submenu.addItem(setActive)
            }

            let update = NSMenuItem(title: "Update Token...", action: #selector(updateToken(_:)), keyEquivalent: "")
            update.target = self
            update.representedObject = account.name
            submenu.addItem(update)
            submenu.addItem(.separator())

            let logout = NSMenuItem(title: "Log Out", action: #selector(logOutAccount(_:)), keyEquivalent: "")
            logout.target = self
            logout.representedObject = account.name
            submenu.addItem(logout)

            // Account item with checkmark if active, bucket name in parentheses
            let title = account.bucket.isEmpty ? account.name : "\(account.name) (\(account.bucket))"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            if account.name == active { item.state = .on }
            menu.addItem(item)
        }
    }

    /// Show "X of Y uploaded" if there are active/completed jobs in the queue.
    private func addQueueSummary(to menu: NSMenu) {
        guard let qm = try? QueueManager() else { return }
        let uploading = (try? qm.listJobs(status: .uploading))?.count ?? 0
        let pending = (try? qm.listJobs(status: .pending))?.count ?? 0
        let completed = (try? qm.listJobs(status: .completed))?.count ?? 0
        let total = uploading + pending + completed
        guard total > 0 else { return }

        let summary = NSMenuItem(title: "\(completed) of \(total) uploaded", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())
    }

    // MARK: - Menu Actions

    @objc private func toggleEnabled() { isEnabled.toggle() }

    @objc private func addAccount() { appDelegate?.showAddAccount() }

    @objc private func setActiveAccount(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let manager = try? AccountManager()
        try? manager?.switchAccount(to: name)
    }

    @objc private func updateToken(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        appDelegate?.showUpdateToken(accountName: name)
    }

    @objc private func logOutAccount(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        appDelegate?.logOut(accountName: name)
    }

    @objc private func showPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }

    private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    // MARK: - Drag-and-Drop Setup (FR-066)

    private func setupDragDrop() {
        guard let button = statusItem.button else { return }
        let dragView = StatusBarDragView(frame: button.bounds)
        dragView.autoresizingMask = [.width, .height]
        dragView.onFilesDropped = { [weak self] urls in self?.handleDroppedFiles(urls) }
        button.addSubview(dragView)
    }

    /// Handle files dropped on the status item. Shows confirmation unless "Never ask again".
    private func handleDroppedFiles(_ urls: [URL]) {
        guard isEnabled else { return }

        // Need an active account to upload
        let config = (try? ConfigManager.load()) ?? R2Config()
        guard let activeName = config.activeAccount,
              let account = config.accounts.first(where: { $0.name == activeName }) else {
            let alert = NSAlert()
            alert.messageText = "No Active Account"
            alert.informativeText = "Set up an account before uploading files."
            alert.runModal()
            return
        }

        // Confirmation dialog (skipped if "Never ask again" was checked)
        let neverAsk = UserDefaults.standard.bool(forKey: "R2Drop.NeverAskConfirmation")
        if !neverAsk {
            guard showDropConfirmation(urls: urls) else { return }
        }

        // Queue uploads for the active account
        queueUploads(urls: urls, account: account)
    }

    /// NSAlert confirmation for dropped files. Returns true if user clicks Upload.
    private func showDropConfirmation(urls: [URL]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        if urls.count == 1, let url = urls.first {
            alert.messageText = "Upload \"\(url.lastPathComponent)\"?"
            alert.informativeText = "Size: \(formatSize(fileSize(url)))"
        } else {
            let total = urls.reduce(UInt64(0)) { $0 + fileSize($1) }
            alert.messageText = "Upload \(urls.count) items?"
            alert.informativeText = "Total size: \(formatSize(total))"
        }
        alert.addButton(withTitle: "Upload")
        alert.addButton(withTitle: "Cancel")

        // "Never ask again" checkbox
        let checkbox = NSButton(checkboxWithTitle: "Never ask again", target: nil, action: nil)
        alert.accessoryView = checkbox
        let response = alert.runModal()
        if checkbox.state == .on {
            UserDefaults.standard.set(true, forKey: "R2Drop.NeverAskConfirmation")
        }
        return response == .alertFirstButtonReturn
    }

    /// Insert upload jobs into queue.db for each dropped file.
    /// Checks for conflicts with existing R2 objects (FR-065).
    /// If an object already exists, prompts the user for Overwrite / Skip / Rename
    /// unless "Apply to all" was previously selected in this session.
    private func queueUploads(urls: [URL], account: ConfigAccount) {
        guard let qm = try? QueueManager() else { return }

        // Get token for head_object checks
        let keychain = KeychainManager()
        let token = try? keychain.getToken(account: account.name)

        for url in urls {
            let name = url.lastPathComponent
            var r2Key = account.path.isEmpty ? name : "\(account.path)/\(name)"

            // Check for conflict if we have credentials (FR-065)
            if let token = token, !account.accountId.isEmpty {
                let resolution = resolveConflict(
                    r2Key: r2Key, fileName: name,
                    localSize: fileSize(url), account: account, token: token
                )
                switch resolution {
                case .skip:
                    continue // Don't queue this file
                case .rename:
                    r2Key = ConflictManager.renamedKey(r2Key)
                case .overwrite:
                    break // Queue as-is, will overwrite
                case nil:
                    break // No conflict — proceed normally
                }
            }

            _ = try? qm.insertJob(
                filePath: url.path, r2Key: r2Key,
                bucket: account.bucket, accountName: account.name,
                totalBytes: fileSize(url)
            )
        }
    }

    /// Check if r2Key already exists and resolve the conflict.
    /// Returns nil if no conflict, or the user's choice if conflict detected.
    private func resolveConflict(
        r2Key: String, fileName: String,
        localSize: UInt64, account: ConfigAccount, token: String
    ) -> ConflictChoice? {
        // Call head_object via FFI (synchronous — Rust blocks internally)
        let client = R2Client()
        guard let info = try? client.headObjectSync(
            accountId: account.accountId, token: token,
            bucket: account.bucket, key: r2Key
        ) else {
            return nil // No existing object or error — no conflict
        }

        // Object exists — check if "Apply to all" was set earlier this session
        if let stored = ConflictManager.shared.storedChoice() {
            return stored
        }

        // Show the conflict dialog
        let objInfo = ExistingObjectInfo(
            contentLength: info.contentLength,
            lastModified: info.lastModifiedDate
        )
        let result = ConflictDialog.show(
            fileName: fileName, localSize: localSize, existingInfo: objInfo
        )
        ConflictManager.shared.recordChoice(result.choice, applyToAll: result.applyToAll)
        return result.choice
    }

    // MARK: - Helpers

    private func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? UInt64 ?? 0
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
