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
        // Use an SF Symbol for the context menu icon.
        // Finder context menus on macOS 13+ support SF Symbols directly.
        // We use a monochrome rendering mode and set as template for proper tinting.
        if let symbolImg = NSImage(systemSymbolName: "icloud.and.arrow.up",
                                     accessibilityDescription: "Send to R2") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let configured = symbolImg.withSymbolConfiguration(config) ?? symbolImg
            configured.isTemplate = true
            item.image = configured
        }
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
        // DISABLED: Compress and Copy URL features not yet implemented

        if !neverAsk {
            let result = showConfirmationDialog(urls: filteredURLs)
            guard result.confirmed else { return }
            // shouldCompress = result.compress  // DISABLED
            // shouldCopyURL = result.copyURL    // DISABLED
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

        // DISABLED: "Compress as ZIP" feature not yet implemented
        // let compressCheck = NSButton(
        //     checkboxWithTitle: "Compress as ZIP",
        //     target: nil, action: nil
        // )
        // compressCheck.frame = NSRect(x: 0, y: 52, width: 300, height: 20)
        // compressCheck.state = .off
        // accessoryView.addSubview(compressCheck)

        // DISABLED: "Copy URL to clipboard" feature not yet implemented
        // let copyURLCheck = NSButton(
        //     checkboxWithTitle: "Copy URL to clipboard",
        //     target: nil, action: nil
        // )
        // copyURLCheck.frame = NSRect(x: 0, y: 30, width: 300, height: 20)
        // copyURLCheck.state = .on
        // accessoryView.addSubview(copyURLCheck)

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
            // DISABLED: Copy URL feature not yet implemented
            // Self.sharedDefaults?.set(false, forKey: Self.copyURLKey)
        }

        return ConfirmResult(
            confirmed: response == .alertFirstButtonReturn,
            compress: false,  // DISABLED: Compress feature not yet implemented
            copyURL: true     // DISABLED: Copy URL feature not yet implemented
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

        // Load exclusion patterns for per-file filtering during folder enumeration
        let config = (try? ConfigManager.load()) ?? R2Config()
        let exclusions = config.preferences.exclusionPatterns

        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDirectory {
                // Recursively enumerate folder contents
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
                    guard !matchesExclusionPattern(fileName, patterns: exclusions) else { continue }
                    let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                    let name = "\(baseName)/\(relativePath)"
                    let pathPrefix = account.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let r2Key = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"
                    let size = fileSize(fileURL)
                    _ = try? qm.insertJob(filePath: fileURL.path, r2Key: r2Key, bucket: account.bucket, accountName: account.name, totalBytes: size)
                }
                continue  // Skip the single-file logic below
            }

            // Single file
            let name = url.lastPathComponent
            // Build the R2 key: account.path prefix + filename
            let pathPrefix = account.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let r2Key = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"
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
                if pattern.hasPrefix("*") {
                    // Suffix match: "*.tmp" matches "file.tmp"
                    let suffix = String(pattern.dropFirst())
                    if filename.hasSuffix(suffix) { return true }
                } else if pattern.hasSuffix("*") {
                    // Prefix match: "._*" matches "._DS_Store"
                    let prefix = String(pattern.dropLast())
                    if filename.hasPrefix(prefix) { return true }
                } else {
                    // Contains match: "foo*bar"
                    let parts = pattern.split(separator: "*", maxSplits: 1)
                    if parts.count == 2 {
                        if filename.hasPrefix(String(parts[0])) && filename.hasSuffix(String(parts[1])) {
                            return true
                        }
                    }
                }
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
