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
        configureMonitoredDirectories()
    }

    // MARK: - Context Menu (FR-017)

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            break
        default:
            return nil
        }

        let menu = NSMenu(title: "R2Drop")
        let item = NSMenuItem(
            title: "Send to R2",
            action: #selector(sendToR2(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = createMenuIcon()
        item.image?.isTemplate = true
        menu.addItem(item)
        return menu
    }

    // MARK: - Send to R2 Action

    /// Called when user clicks "Send to R2" in the Finder context menu.
    /// Supports bulk selection (FR-018).
    @objc func sendToR2(_ sender: AnyObject?) {
        let controller = FIFinderSyncController.default()
        let selectedURLs = controller.selectedItemURLs() ?? []
        let targetURLs: [URL]

        if !selectedURLs.isEmpty {
            targetURLs = selectedURLs
        } else if let targetedURL = controller.targetedURL() {
            // Container/context clicks may not populate selectedItemURLs().
            targetURLs = [targetedURL]
        } else {
            return
        }

        // Load config to get active account
        let config: R2Config
        do {
            config = try ConfigManager.load()
        } catch {
            NSLog("R2Drop FinderExtension: failed to load config: %@", String(describing: error))
            showNoAccountAlert()
            return
        }
        guard let activeName = config.activeAccount,
              let account = config.accounts.first(where: { $0.name == activeName }) else {
            showNoAccountAlert()
            return
        }

        // Filter out excluded files (FR-049)
        let exclusions = config.preferences.exclusionPatterns
        let filteredURLs = targetURLs.filter { url in
            !matchesExclusionPattern(url.lastPathComponent, patterns: exclusions)
        }
        guard !filteredURLs.isEmpty else { return }

        // Confirmation dialog (FR-019), skipped if "Never ask again" (FR-020)
        let neverAsk = Self.sharedDefaults?.bool(forKey: Self.neverAskKey) ?? false
        if !neverAsk {
            let result = showConfirmationDialog(urls: filteredURLs)
            guard result.confirmed else { return }
        }

        // Queue uploads via App Groups shared queue.db (FR-021)
        queueUploads(urls: filteredURLs, account: account)

        // Best-effort: wake the main app so Finder-queued jobs are transferred immediately.
        wakeMainAppForQueuedUploads()
    }

    // MARK: - Confirmation Dialog (FR-019)

    /// Result of the confirmation dialog.
    private struct ConfirmResult {
        let confirmed: Bool
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
        }

        return ConfirmResult(
            confirmed: response == .alertFirstButtonReturn
        )
    }

    // MARK: - Queue Uploads (FR-021)

    /// Write UploadJob records to the shared App Groups queue.db.
    /// The main app polls this database and transfers jobs for processing.
    private func queueUploads(
        urls: [URL],
        account: ConfigAccount
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

        NSLog("R2Drop FinderExtension: queued %ld item(s) for account %@",
              urls.count, account.name)
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

    /// Open a lightweight deep link so the main app can transfer Finder-queued jobs.
    private func wakeMainAppForQueuedUploads() {
        guard let url = URL(string: "\(R2CoreConstants.urlScheme)://status") else { return }
        _ = NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    /// Finder Sync needs explicit monitored roots before it will show menus.
    /// Using "/" is unreliable in practice; prefer user home + mounted volumes.
    private func configureMonitoredDirectories() {
        var monitored = Set<URL>()

        let sandboxHome = NSHomeDirectory()
        let userHome = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL

        NSLog("R2Drop FinderExtension: sandboxHome=%@ userHome=%@",
              sandboxHome, userHome.path)

        monitored.insert(
            userHome
        )

        // Include mounted external/network volumes where users often drag assets.
        monitored.insert(URL(fileURLWithPath: "/Volumes", isDirectory: true))

        if let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) {
            for volume in mountedVolumes {
                // Finder Sync can behave inconsistently when monitoring "/".
                // Home + /Volumes covers normal user workflows more reliably.
                if volume.path == "/" { continue }
                monitored.insert(volume.standardizedFileURL)
            }
        }

        FIFinderSyncController.default().directoryURLs = monitored
        NSLog("R2Drop FinderExtension: Monitoring \(monitored.count) roots")
    }

    /// Get the file size in bytes. Returns 0 for directories or errors.
    private func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? UInt64 ?? 0
    }

    /// Format bytes as a human-readable string (e.g. "4.2 MB").
    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Context Menu Icon

    /// Prefer a system template symbol so Finder renders a native-looking menu icon.
    private func createMenuIcon() -> NSImage {
        if #available(macOS 11.0, *),
           let symbol = NSImage(
               systemSymbolName: "square.and.arrow.up",
               accessibilityDescription: "Send to R2"
           ) {
            let configured = symbol.withSymbolConfiguration(
                .init(pointSize: 12, weight: .regular)
            ) ?? symbol
            configured.size = NSSize(width: 16, height: 16)
            configured.isTemplate = true
            return configured
        }

        return createFallbackTemplateIcon()
    }

    /// Create a 16x16 monochrome template image for the Finder context menu.
    /// Draws an upward arrow over a tray shape (standard "upload" icon).
    /// Returned image has isTemplate = true so macOS auto-tints for light/dark mode.
    private func createFallbackTemplateIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Upward arrow shaft (centered, from bottom-ish to top)
            let shaft = NSBezierPath()
            shaft.move(to: NSPoint(x: 8, y: 3))
            shaft.line(to: NSPoint(x: 8, y: 11))
            shaft.lineWidth = 1.5
            shaft.lineCapStyle = .round
            shaft.stroke()

            // Arrow head (chevron pointing up)
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 4.5, y: 7))
            head.line(to: NSPoint(x: 8, y: 3))
            head.line(to: NSPoint(x: 11.5, y: 7))
            head.lineWidth = 1.5
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.stroke()

            // Tray base (U-shape at bottom)
            let tray = NSBezierPath()
            tray.move(to: NSPoint(x: 2, y: 10))
            tray.line(to: NSPoint(x: 2, y: 14))
            tray.line(to: NSPoint(x: 14, y: 14))
            tray.line(to: NSPoint(x: 14, y: 10))
            tray.lineWidth = 1.5
            tray.lineCapStyle = .round
            tray.lineJoinStyle = .round
            tray.stroke()

            return true
        }
        image.size = size
        image.isTemplate = true
        return image
    }
}
