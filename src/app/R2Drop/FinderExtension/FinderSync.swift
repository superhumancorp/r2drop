// R2Drop/FinderExtension/FinderSync.swift
// Finder Sync Extension providing "Send to R2" context menu item (FR-017).
// Communicates with main app via shared SQLite (App Groups).
// Supports bulk file/folder selection (FR-018), confirmation dialog (FR-019),
// "Never ask again" preference (FR-020), and exclusion pattern filtering (FR-049).

import Cocoa
import FinderSync
import R2Core

class FinderSync: FIFinderSync {

    // MARK: - UserDefaults keys (shared via App Groups)

    /// UserDefaults suite shared between main app and Finder extension.
    private static let sharedDefaults = UserDefaults(
        suiteName: R2CoreConstants.appGroup
    )

    /// Key for the "Never ask again" preference (FR-020).
    private static let neverAskKey = "R2Drop.NeverAskConfirmation"

    /// Key for the "Copy URL to clipboard" default toggle state.
    private static let copyURLKey = "R2Drop.CopyURLOnUpload"

    // MARK: - Init

    override init() {
        super.init()
        // Monitor the entire filesystem so the context menu appears everywhere.
        // FIFinderSync requires at least one directory URL to activate.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/")
        ]
    }

    // MARK: - Context Menu (FR-017)

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "R2Drop")
        let item = NSMenuItem(
            title: "Send to R2",
            action: #selector(sendToR2(_:)),
            keyEquivalent: ""
        )
        item.image = NSImage(
            systemSymbolName: "arrow.up.circle",
            accessibilityDescription: "Upload to R2"
        )
        menu.addItem(item)
        return menu
    }

    // MARK: - Send to R2 Action

    /// Called when user clicks "Send to R2" in the Finder context menu.
    /// Supports bulk selection (FR-018).
    @objc func sendToR2(_ sender: AnyObject?) {
        guard let selectedURLs = FIFinderSyncController.default().selectedItemURLs(),
              !selectedURLs.isEmpty else {
            return
        }

        // Load config to get active account
        let config = (try? ConfigManager.load()) ?? R2Config()
        guard let activeName = config.activeAccount,
              let account = config.accounts.first(where: { $0.name == activeName }) else {
            showNoAccountAlert()
            return
        }

        // Filter out excluded files (FR-049)
        let exclusions = config.preferences.exclusionPatterns
        let filteredURLs = selectedURLs.filter { url in
            !matchesExclusionPattern(url.lastPathComponent, patterns: exclusions)
        }
        guard !filteredURLs.isEmpty else { return }

        // Confirmation dialog (FR-019), skipped if "Never ask again" (FR-020)
        let neverAsk = Self.sharedDefaults?.bool(forKey: Self.neverAskKey) ?? false
        var shouldCompress = false
        var shouldCopyURL = true

        if !neverAsk {
            let result = showConfirmationDialog(urls: filteredURLs)
            guard result.confirmed else { return }
            shouldCompress = result.compress
            shouldCopyURL = result.copyURL
        } else {
            shouldCopyURL = Self.sharedDefaults?.bool(forKey: Self.copyURLKey) ?? true
        }

        // Queue uploads via App Groups shared queue.db (FR-021)
        queueUploads(
            urls: filteredURLs,
            account: account,
            compress: shouldCompress,
            copyURL: shouldCopyURL
        )
    }

    // MARK: - Confirmation Dialog (FR-019)

    /// Result of the confirmation dialog.
    private struct ConfirmResult {
        let confirmed: Bool
        let compress: Bool
        let copyURL: Bool
    }

    /// Show the upload confirmation dialog with toggles.
    /// Returns whether the user confirmed and their toggle selections.
    private func showConfirmationDialog(urls: [URL]) -> ConfirmResult {
        let alert = NSAlert()
        alert.alertStyle = .informational

        // Message: single file shows name+size, multiple shows count+total
        if urls.count == 1, let url = urls.first {
            alert.messageText = "Upload \"\(url.lastPathComponent)\" to R2?"
            let size = fileSize(url)
            alert.informativeText = "Size: \(formatSize(size))"
        } else {
            let total = urls.reduce(UInt64(0)) { $0 + fileSize($1) }
            alert.messageText = "Upload \(urls.count) items to R2?"
            alert.informativeText = "Total size: \(formatSize(total))"
        }

        alert.addButton(withTitle: "Upload")
        alert.addButton(withTitle: "Cancel")

        // Accessory view with toggles
        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 76))

        // "Compress as ZIP" toggle (default off)
        let compressCheck = NSButton(
            checkboxWithTitle: "Compress as ZIP",
            target: nil, action: nil
        )
        compressCheck.frame = NSRect(x: 0, y: 52, width: 300, height: 20)
        compressCheck.state = .off
        accessoryView.addSubview(compressCheck)

        // "Copy URL to clipboard" toggle (default on)
        let copyURLCheck = NSButton(
            checkboxWithTitle: "Copy URL to clipboard",
            target: nil, action: nil
        )
        copyURLCheck.frame = NSRect(x: 0, y: 30, width: 300, height: 20)
        copyURLCheck.state = .on
        accessoryView.addSubview(copyURLCheck)

        // "Never ask again" checkbox (default off)
        let neverAskCheck = NSButton(
            checkboxWithTitle: "Never ask again",
            target: nil, action: nil
        )
        neverAskCheck.frame = NSRect(x: 0, y: 4, width: 300, height: 20)
        neverAskCheck.state = .off
        accessoryView.addSubview(neverAskCheck)

        alert.accessoryView = accessoryView
        let response = alert.runModal()

        // Save "Never ask again" preference if checked (FR-020)
        if neverAskCheck.state == .on {
            Self.sharedDefaults?.set(true, forKey: Self.neverAskKey)
            // Also save the copy URL preference for future silent uploads
            Self.sharedDefaults?.set(
                copyURLCheck.state == .on,
                forKey: Self.copyURLKey
            )
        }

        return ConfirmResult(
            confirmed: response == .alertFirstButtonReturn,
            compress: compressCheck.state == .on,
            copyURL: copyURLCheck.state == .on
        )
    }

    // MARK: - Queue Uploads (FR-021)

    /// Write UploadJob records to the shared App Groups queue.db.
    /// The main app polls this database and transfers jobs for processing.
    private func queueUploads(
        urls: [URL],
        account: ConfigAccount,
        compress: Bool,
        copyURL: Bool
    ) {
        guard let qm = try? QueueManager(appGroup: R2CoreConstants.appGroup) else {
            NSLog("R2Drop FinderExtension: Failed to open shared queue.db")
            return
        }

        for url in urls {
            let name = url.lastPathComponent
            // Build the R2 key: account.path prefix + filename
            let r2Key = account.path.isEmpty ? name : "\(account.path)/\(name)"
            let size = fileSize(url)

            _ = try? qm.insertJob(
                filePath: url.path,
                r2Key: r2Key,
                bucket: account.bucket,
                accountName: account.name,
                totalBytes: size
            )
        }
    }

    // MARK: - Exclusion Patterns (FR-049)

    /// Check if a filename matches any of the exclusion patterns.
    /// Supports exact matches and simple wildcard patterns (e.g. "._*").
    private func matchesExclusionPattern(
        _ filename: String,
        patterns: [String]
    ) -> Bool {
        for pattern in patterns {
            if pattern.contains("*") {
                // Simple wildcard: "._*" matches any file starting with "._"
                let prefix = pattern.replacingOccurrences(of: "*", with: "")
                if filename.hasPrefix(prefix) { return true }
            } else {
                // Exact match
                if filename == pattern { return true }
            }
        }
        return false
    }

    // MARK: - Alerts

    /// Show an alert when no account is configured.
    private func showNoAccountAlert() {
        let alert = NSAlert()
        alert.messageText = "No Active Account"
        alert.informativeText = "Open R2Drop and set up an account before uploading."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Helpers

    /// Get the file size in bytes. Returns 0 for directories or errors.
    private func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? UInt64 ?? 0
    }

    /// Format bytes as a human-readable string (e.g. "4.2 MB").
    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
