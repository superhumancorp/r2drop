// R2Drop/App/MenuBarController.swift
// Manages the NSStatusItem in the macOS menu bar.
// Handles: persistent icon (FR-034), pulsing animation during uploads (FR-035),
// dropdown menu with toggle/accounts/queue/prefs/quit (FR-036),
// and drag-and-drop file uploads (FR-066).
// Uses a custom template image from the asset catalog for light/dark adaptation.

import AppKit
import CryptoKit
import R2Bridge
import R2Core

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    /// Direct reference to AppDelegate — avoids fragile NSApp.delegate cast
    /// which can fail with SwiftUI's @NSApplicationDelegateAdaptor wrapper.
    private weak var appDelegateRef: AppDelegate?
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
        // Try custom asset first, fall back to SF Symbol if asset catalog fails
        if let img = NSImage(named: "MenuBarIcon") {
            img.isTemplate = true
            return img
        }
        // SF Symbol fallback — icloud.and.arrow.up is a reasonable stand-in
        let fallback = NSImage(systemSymbolName: "icloud.and.arrow.up", accessibilityDescription: "R2Drop")
        fallback?.isTemplate = true
        return fallback
    }()

    // MARK: - Init

    init(appDelegate: AppDelegate) {
        self.appDelegateRef = appDelegate
        super.init()
        #if DEBUG
        R2Log.menubar.debug("MenuBarController.init")
        #endif
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
        #if DEBUG
        R2Log.menubar.debug("setupStatusItem: icon=\(Self.menuBarIcon != nil ? "loaded" : "nil")")
        #endif
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
        #if DEBUG
        if wasUploading != isUploading {
            R2Log.menubar.debug("Upload state changed: \(wasUploading) → \(self.isUploading)")
        }
        #endif
    }

    private func hasActiveUploads() -> Bool {
        guard let qm = try? QueueManager() else { return false }
        let jobs = (try? qm.listJobs(status: .uploading)) ?? []
        return !jobs.isEmpty
    }

    // MARK: - NSMenuDelegate

    /// Rebuild the menu each time it opens for fresh data.
    func menuWillOpen(_ menu: NSMenu) {
        // P0: menu_bar_opened
        let config = (try? ConfigManager.load()) ?? R2Config()
        TelemetryService.shared.track("menu_bar_opened", properties: [
            "account_count": config.accounts.count,
            "has_active_uploads": isUploading,
            "is_enabled": isEnabled
        ])
        rebuildMenu(menu)
    }

    // MARK: - Menu Construction (FR-036)

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. Tailscale-style header: app name, status text, toggle switch
        let headerView = MenuBarHeaderView()
        headerView.isEnabled = isEnabled
        headerView.onToggle = { [weak self] enabled in
            self?.isEnabled = enabled
        }
        let headerItem = NSMenuItem()
        headerItem.view = headerView
        menu.addItem(headerItem)
        menu.addItem(.separator())

        // 2. Account section — deduplicate by name to handle legacy config dupes
        let config = (try? ConfigManager.load()) ?? R2Config()
        let uniqueAccounts = deduplicateAccounts(config.accounts)
        if !uniqueAccounts.isEmpty {
            addAccountItems(to: menu, accounts: uniqueAccounts, active: config.activeAccount)
            menu.addItem(.separator())
        }

        // Add Account
        let addItem = NSMenuItem(title: "Add Account...", action: #selector(addAccount), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)

        // Manual upload picker (files and folders)
        let uploadItem = NSMenuItem(title: "Upload File(s)...", action: #selector(openUploadPicker), keyEquivalent: "")
        uploadItem.target = self
        menu.addItem(uploadItem)
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

    /// Add per-account submenu items. Tailscale-style: only the active account
    /// gets a checkmark; others are shown as selectable options.
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

            // Tailscale-style: checkmark on active, plain for others
            let title = account.bucket.isEmpty ? account.name : "\(account.name) (\(account.bucket))"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            if account.name == active { item.state = .on }
            menu.addItem(item)
        }
    }

    /// Remove duplicate accounts by name, keeping the last occurrence.
    /// Handles legacy config files that accumulated duplicates.
    private func deduplicateAccounts(_ accounts: [ConfigAccount]) -> [ConfigAccount] {
        var seen = Set<String>()
        var result: [ConfigAccount] = []
        for account in accounts.reversed() {
            if !seen.contains(account.name) {
                seen.insert(account.name)
                result.append(account)
            }
        }
        return result.reversed()
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


    @objc private func addAccount() { appDelegate?.showAddAccount() }

    @objc private func openUploadPicker() {
        // P0: menu_upload_picker_opened
        TelemetryService.shared.track("menu_upload_picker_opened", properties: [
            "surface": "menu_bar"
        ])
        let panel = NSOpenPanel()
        panel.title = "Upload to R2"
        panel.message = "Select one or more files and/or folders to upload."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK else { return }

        // P0: menu_upload_picker_selection_submitted
        let hasDir = panel.urls.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
        TelemetryService.shared.track("menu_upload_picker_selection_submitted", properties: [
            "file_count": panel.urls.count,
            "contains_directory": hasDir
        ])
        queueUserSelectedURLs(panel.urls)
    }

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
        AppDelegate.openSettingsWindow(reason: "menu")
    }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }

    private var appDelegate: AppDelegate? { appDelegateRef }

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
        #if DEBUG
        R2Log.menubar.debug("handleDroppedFiles: \(urls.count) files")
        #endif

        // P0: menu_bar_files_dropped
        let hasDirInDrop = urls.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
        TelemetryService.shared.track("menu_bar_files_dropped", properties: [
            "file_count": urls.count,
            "contains_directory": hasDirInDrop,
            "is_enabled": isEnabled
        ])
        guard isEnabled else { return }

        // Need an active account to upload
        let config = (try? ConfigManager.load()) ?? R2Config()
        guard let activeName = config.activeAccount,
              let account = config.accounts.first(where: { $0.name == activeName }) else {

            // P1: upload_no_active_account_blocked
            TelemetryService.shared.track("upload_no_active_account_blocked", properties: [
                "entrypoint": "menu_bar_drop"
            ])

            let alert = NSAlert()
            alert.messageText = "No Active Account"
            alert.informativeText = "Set up an account before uploading files."
            alert.runModal()
            return
        }

        // Confirmation dialog (skipped if "Never ask again" was checked)
        let neverAsk = UserDefaults(suiteName: "group.com.superhumancorp.r2drop")?.bool(forKey: "R2Drop.NeverAskConfirmation") ?? false
        if !neverAsk {
            guard showDropConfirmation(urls: urls) else { return }
        }

        // Queue uploads for the active account on an async task so conflict
        // checks (network HEAD calls) do not block the menu bar UI thread.
        Task { [weak self] in
            await self?.queueUploads(urls: urls, account: account)
        }
    }

    /// Queue user-selected uploads from any UI entry point (menu picker, Dock open, drag-drop).
    /// Uses the same validation + confirmation flow as menu bar drag-and-drop.
    func queueUserSelectedURLs(_ urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return }
        handleDroppedFiles(fileURLs)
    }

    /// NSAlert confirmation for dropped files. Returns true if user clicks Upload.
    private func showDropConfirmation(urls: [URL]) -> Bool {
        let hasDir = urls.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
        let neverAskPre = UserDefaults(suiteName: "group.com.superhumancorp.r2drop")?.bool(forKey: "R2Drop.NeverAskConfirmation") ?? false

        // P0: upload_confirmation_shown
        TelemetryService.shared.track("upload_confirmation_shown", properties: [
            "entrypoint": "menu_bar_drop",
            "file_count": urls.count,
            "contains_directory": hasDir,
            "never_ask_preexisting": neverAskPre
        ])

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
            UserDefaults(suiteName: "group.com.superhumancorp.r2drop")?.set(true, forKey: "R2Drop.NeverAskConfirmation")
        }

        // P0: upload_confirmation_result
        let uploaded = response == .alertFirstButtonReturn
        TelemetryService.shared.track("upload_confirmation_result", properties: [
            "entrypoint": "menu_bar_drop",
            "result": uploaded ? "confirmed" : "cancelled",
            "never_ask_checked": checkbox.state == .on
        ])

        return uploaded
    }
    /// Insert upload jobs into queue.db for each dropped file or folder.
    /// Recursively enumerates folder contents, applies exclusion patterns (FR-049),
    /// and checks for conflicts with existing R2 objects (FR-065).
    /// Heavy work runs off-main; only conflict dialogs bounce back to MainActor.
    private func queueUploads(urls: [URL], account: ConfigAccount) async {
        #if DEBUG
        R2Log.menubar.debug("queueUploads: \(urls.count) items to account=\(account.name) bucket=\(account.bucket)")
        #endif

        // P0: upload_enqueue_requested
        let hasDirInQueue = urls.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
        TelemetryService.shared.track("upload_enqueue_requested", properties: [
            "entrypoint": "menu_bar_drop",
            "file_count": urls.count,
            "contains_directory": hasDirInQueue,
            "account_name_hash": TelemetrySanitizer.hash(account.name),
            "bucket_hash": TelemetrySanitizer.hash(account.bucket)
        ])

        let snapshot = MenuBarUploadQueueWorker.AccountSnapshot(account)
        _ = await Task.detached(priority: .userInitiated) {
            await MenuBarUploadQueueWorker.queue(urls: urls, account: snapshot)
        }.value
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

// MARK: - Menu Upload Worker (off-main)

/// Background worker for menu bar initiated uploads.
/// Keeps file enumeration, queue DB inserts, and R2 HEAD checks off the main actor.
private enum MenuBarUploadQueueWorker {

    struct AccountSnapshot: Sendable {
        let name: String
        let bucket: String
        let path: String
        let accountId: String
        let tokenId: String

        init(_ account: ConfigAccount) {
            self.name = account.name
            self.bucket = account.bucket
            self.path = account.path
            self.accountId = account.accountId
            self.tokenId = account.tokenId
        }
    }

    static func queue(urls: [URL], account: AccountSnapshot) async {
        guard let qm = try? QueueManager() else { return }

        let config = (try? ConfigManager.load()) ?? R2Config()
        let exclusions = config.preferences.exclusionPatterns
        let token = try? KeychainManager().getToken(account: account.name)
        var queuedAny = false
        var jobsEnqueued = 0
        var filesSkippedExcluded = 0
        var containsDirectory = false

        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory { containsDirectory = true }

            if isDirectory {
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                let baseName = url.lastPathComponent
                while let fileURL = enumerator?.nextObject() as? URL {
                    let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                    guard isFile else { continue }
                    let fileName = fileURL.lastPathComponent
                    guard !matchesExclusionPattern(fileName, patterns: exclusions) else {
                        filesSkippedExcluded += 1
                        continue
                    }
                    let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                    let name = "\(baseName)/\(relativePath)"
                    let pathPrefix = account.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let r2Key = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"
                    if (try? qm.insertJob(
                        filePath: fileURL.path,
                        r2Key: r2Key,
                        bucket: account.bucket,
                        accountName: account.name,
                        totalBytes: fileSize(fileURL)
                    )) != nil {
                        queuedAny = true
                        jobsEnqueued += 1
                    }
                }
                continue
            }

            let name = url.lastPathComponent
            guard !matchesExclusionPattern(name, patterns: exclusions) else {
                filesSkippedExcluded += 1
                continue
            }
            let pathPrefix = account.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var r2Key = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"

            if let token, !account.accountId.isEmpty, !account.tokenId.isEmpty {
                let resolution = await resolveConflict(
                    r2Key: r2Key,
                    fileName: name,
                    localSize: fileSize(url),
                    account: account,
                    token: token
                )
                switch resolution {
                case .skip:
                    continue
                case .rename:
                    r2Key = ConflictManager.renamedKey(r2Key)
                case .overwrite:
                    break
                case nil:
                    break
                }
            }

            if (try? qm.insertJob(
                filePath: url.path,
                r2Key: r2Key,
                bucket: account.bucket,
                accountName: account.name,
                totalBytes: fileSize(url)
            )) != nil {
                queuedAny = true
                jobsEnqueued += 1
            }
        }

        // P0: upload_jobs_enqueued
        await MainActor.run {
            TelemetryService.shared.track("upload_jobs_enqueued", properties: [
                "entrypoint": "menu_bar",
                "jobs_enqueued": jobsEnqueued,
                "files_skipped_excluded": filesSkippedExcluded,
                "contains_directory": containsDirectory
            ])
        }

        if queuedAny {
            await MainActor.run {
                NotificationCenter.default.post(name: .r2dropQueueDidChange, object: nil)
            }
        }
    }

    private static func resolveConflict(
        r2Key: String,
        fileName: String,
        localSize: UInt64,
        account: AccountSnapshot,
        token: String
    ) async -> ConflictChoice? {
        let secretAccessKey = sha256Hex(token)
        guard let info = await headObjectWithTimeout(
            accountId: account.accountId,
            accessKeyId: account.tokenId,
            secretAccessKey: secretAccessKey,
            bucket: account.bucket,
            key: r2Key,
            timeoutSeconds: 10
        ) else {
            return nil
        }

        let existingInfo = ExistingObjectInfo(
            contentLength: info.contentLength,
            lastModified: info.lastModifiedDate
        )

        return await MainActor.run {
            if let stored = ConflictManager.shared.storedChoice() {
                return stored
            }
            let result = ConflictDialog.show(
                fileName: fileName,
                localSize: localSize,
                existingInfo: existingInfo
            )
            ConflictManager.shared.recordChoice(result.choice, applyToAll: result.applyToAll)
            return result.choice
        }
    }

    private static func headObjectWithTimeout(
        accountId: String,
        accessKeyId: String,
        secretAccessKey: String,
        bucket: String,
        key: String,
        timeoutSeconds: UInt64
    ) async -> R2ObjectInfo? {
        let client = R2Client()
        return await withTaskGroup(of: R2ObjectInfo?.self, returning: R2ObjectInfo?.self) { group in
            group.addTask {
                try? await client.headObject(
                    accountId: accountId,
                    accessKeyId: accessKeyId,
                    secretAccessKey: secretAccessKey,
                    bucket: bucket,
                    key: key
                )
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func matchesExclusionPattern(_ filename: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if pattern.contains("*") {
                if pattern.hasPrefix("*") {
                    let suffix = String(pattern.dropFirst())
                    if filename.hasSuffix(suffix) { return true }
                } else if pattern.hasSuffix("*") {
                    let prefix = String(pattern.dropLast())
                    if filename.hasPrefix(prefix) { return true }
                } else {
                    let parts = pattern.split(separator: "*", maxSplits: 1)
                    if parts.count == 2,
                       filename.hasPrefix(String(parts[0])) &&
                       filename.hasSuffix(String(parts[1])) {
                        return true
                    }
                }
            } else if filename == pattern {
                return true
            }
        }
        return false
    }

    private static func sha256Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? UInt64 ?? 0
    }
}
