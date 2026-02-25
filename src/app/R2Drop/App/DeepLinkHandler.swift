// R2Drop/App/DeepLinkHandler.swift
// Parses and routes r2drop:// deep link URLs to the appropriate app actions.
// Supports: upload, preferences, account switching, browse, auth, status.
// Security: Deep links cannot exfiltrate credentials (FR-059).
// Upload links validate that the path exists and is readable (FR-060).

import AppKit
import R2Core

/// Routes `r2drop://` deep links to app actions (US-022).
///
/// Supported URLs:
///   r2drop://upload?path=<path>[&compress=true]
///   r2drop://preferences[/queue|/accounts|/settings|/history|/about]
///   r2drop://account?name=<name>
///   r2drop://browse[?account=<name>]
///   r2drop://auth/setup
///   r2drop://status
@MainActor
enum DeepLinkHandler {

    /// Parse a URL and execute the corresponding action.
    /// Returns true if the URL was handled, false otherwise.
    @discardableResult
    static func handle(_ url: URL, appDelegate: AppDelegate) -> Bool {
        guard url.scheme == "r2drop" else { return false }

        // host is the first path component (e.g. "upload", "preferences")
        guard let host = url.host else { return false }

        switch host {
        case "upload":
            return handleUpload(url: url)
        case "preferences":
            return handlePreferences(url: url)
        case "account":
            return handleAccountSwitch(url: url)
        case "browse":
            return handleBrowse(url: url)
        case "auth":
            return handleAuth(url: url, appDelegate: appDelegate)
        case "status":
            // Health check — app is running if we get here.
            return true
        default:
            return false
        }
    }

    // MARK: - Upload (FR-060)

    /// Queue a file for upload. Validates path exists and is readable.
    /// Respects the confirmation dialog unless "Never ask again" is set.
    private static func handleUpload(url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let pathParam = components?.queryItems?.first(where: { $0.name == "path" })?.value else {
            return false
        }

        // FR-060: Validate that path exists and is readable
        let filePath = (pathParam as NSString).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            showAlert(
                title: "File Not Found",
                message: "The path \"\(pathParam)\" does not exist or is not readable."
            )
            return false
        }

        // Need an active account
        let config = (try? ConfigManager.load()) ?? R2Config()
        guard let activeName = config.activeAccount,
              let account = config.accounts.first(where: { $0.name == activeName }) else {
            showAlert(
                title: "No Active Account",
                message: "Set up an account before uploading files."
            )
            return false
        }

        // Check for compress flag
        let compress = components?.queryItems?.first(where: { $0.name == "compress" })?.value == "true"

        // Confirmation dialog (skipped if "Never ask again")
        let neverAsk = UserDefaults(suiteName: "group.com.superhumancorp.r2drop")?.bool(forKey: "R2Drop.NeverAskConfirmation") ?? false
        if !neverAsk {
            let fileName = fileURL.lastPathComponent
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = attrs?[.size] as? UInt64 ?? 0
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            let msg = compress
                ? "Upload \"\(fileName)\" (\(sizeStr)) compressed as ZIP?"
                : "Upload \"\(fileName)\" (\(sizeStr))?"

            guard showConfirmation(title: "Confirm Upload", message: msg) else {
                return true // handled but user cancelled
            }
        }

        // Handle ZIP compression if requested
        let uploadURL: URL
        if compress {
            // Create temporary ZIP archive
            let tempDir = FileManager.default.temporaryDirectory
            let zipName = fileURL.lastPathComponent + ".zip"
            let zipURL = tempDir.appendingPathComponent(zipName)
            try? FileManager.default.removeItem(at: zipURL)
            do {
                try compressToZip(source: fileURL, destination: zipURL)
                uploadURL = zipURL
            } catch {
                showAlert(title: "Compression Failed", message: "Could not create ZIP archive: \(error.localizedDescription)")
                return true
            }
        } else {
            uploadURL = fileURL
        }
        queueFile(fileURL: uploadURL, account: account)
        return true
    }

    // MARK: - Preferences

    /// Open the Preferences window, optionally to a specific tab.
    /// URL path segments: /queue, /accounts, /settings, /history, /about
    private static func handlePreferences(url: URL) -> Bool {
        // Parse tab from path: r2drop://preferences/queue → "queue"
        let pathSegment = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if !pathSegment.isEmpty {
            let tab: SettingsTab? = {
                switch pathSegment {
                case "queue": return .queue
                case "accounts": return .accounts
                case "settings": return .settings
                case "history": return .history
                case "about": return .about
                default: return nil
                }
            }()
            if let tab = tab {
                SelectedTabStore.shared.requestedTab = tab
            }
        }

        openPreferencesWindow()
        return true
    }

    // MARK: - Account Switch

    /// Switch the active account by name.
    private static func handleAccountSwitch(url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let name = components?.queryItems?.first(where: { $0.name == "name" })?.value else {
            return false
        }

        guard let manager = try? AccountManager() else { return false }
        let switched = (try? manager.switchAccount(to: name)) ?? false
        if !switched {
            showAlert(
                title: "Account Not Found",
                message: "No account named \"\(name)\" is configured."
            )
        }
        return true
    }

    // MARK: - Browse (open Cloudflare dashboard)

    /// Open the R2 bucket in Cloudflare dashboard.
    /// Optionally accepts ?account=<name>, otherwise uses active account.
    private static func handleBrowse(url: URL) -> Bool {
        let config = (try? ConfigManager.load()) ?? R2Config()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let accountName = components?.queryItems?.first(where: { $0.name == "account" })?.value
            ?? config.activeAccount

        guard let name = accountName,
              let account = config.accounts.first(where: { $0.name == name }) else {
            showAlert(
                title: "No Account",
                message: "No active account to browse."
            )
            return false
        }

        // Construct Cloudflare dashboard URL (FR-040 pattern)
        let dashURL = "https://dash.cloudflare.com/\(account.accountId)/r2/default/buckets/\(account.bucket)"
        if let browseURL = URL(string: dashURL) {
            NSWorkspace.shared.open(browseURL)
        }
        return true
    }

    // MARK: - Auth Setup

    /// Open the token setup wizard. Requires user interaction (FR-059).
    private static func handleAuth(url: URL, appDelegate: AppDelegate) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path == "setup" else { return false }

        // FR-059: This opens a wizard that requires user action.
        // It does not auto-accept or modify credentials.
        appDelegate.showAddAccount()
        return true
    }

    // MARK: - Helpers

    /// Compress a file or directory into a ZIP archive.
    /// Uses Process to call the system `zip` command (available on all macOS).
    private static func compressToZip(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source.deletingLastPathComponent()
        process.arguments = ["-r", destination.path, source.lastPathComponent]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "R2Drop", code: Int(process.terminationStatus),
                           userInfo: [NSLocalizedDescriptionKey: "zip command failed"])
        }
    }

    /// Insert an upload job into queue.db for the active account.
    private static func queueFile(fileURL: URL, account: ConfigAccount) {
        guard let qm = try? QueueManager() else { return }
        let name = fileURL.lastPathComponent
        let pathPrefix = account.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let r2Key = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = attrs?[.size] as? UInt64 ?? 0
        _ = try? qm.insertJob(
            filePath: fileURL.path, r2Key: r2Key,
            bucket: account.bucket, accountName: account.name,
            totalBytes: size
        )
    }

    /// Open the Preferences window and bring the app to front.
    private static func openPreferencesWindow() {
        AppDelegate.openSettingsWindow()
    }

    /// Show an informational alert.
    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Show a confirmation alert. Returns true if user clicks "OK".
    private static func showConfirmation(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Upload")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
