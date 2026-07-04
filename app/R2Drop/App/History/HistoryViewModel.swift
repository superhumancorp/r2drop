// R2Drop/App/History/HistoryViewModel.swift
// ViewModel for the History tab in Preferences (US-020, FR-052 through FR-054).
// Loads completed uploads from history.db via HistoryManager.
// Supports search filtering, URL copying, and clearing all history.

import AppKit
import Foundation
import R2Core

@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: - Published State

    /// History entries to display, already filtered and sorted (most recent first).
    @Published var entries: [HistoryEntry] = []

    /// Current search text for filtering by file name (FR-052).
    @Published var searchText: String = ""

    // MARK: - Lifecycle

    /// Load all history entries (or filtered by search text).
    func load() {
        #if DEBUG
            R2Log.ui.debug("HistoryViewModel: load search=\(self.searchText)")
        #endif
        guard let hm = try? HistoryManager() else {
            entries = []
            return
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            entries = (try? hm.listEntries()) ?? []
        } else {
            entries = (try? hm.search(query: trimmed)) ?? []
        }
    }

    // MARK: - Actions

    /// Copy the URL for an entry to the clipboard (FR-053).
    /// Uses custom domain if configured, otherwise the stored R2 URL.
    func copyURL(for entry: HistoryEntry) {
        #if DEBUG
            R2Log.ui.debug("HistoryViewModel: copyURL entry=\(entry.fileName)")
        #endif
        let url = resolveURL(for: entry)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    /// Clear all history entries (FR-054).
    func clearHistory() {
        #if DEBUG
            R2Log.ui.debug("HistoryViewModel: clearHistory")
        #endif
        guard let hm = try? HistoryManager() else { return }
        _ = try? hm.clear()
        entries = []
    }

    // MARK: - Helpers

    /// Resolve the display URL for an entry.
    /// Prefers the account's custom domain over the stored R2 public URL (FR-053).
    /// Percent-encodes each path segment of the r2Key per RFC 3986.
    func resolveURL(for entry: HistoryEntry) -> String {
        let config = (try? ConfigManager.load()) ?? R2Config()
        if let account = config.accounts.first(where: { $0.name == entry.accountName }),
            let domain = account.customDomain, !domain.isEmpty
        {
            // Build URL from custom domain + r2Key.
            // Percent-encode each segment without encoding '/' separators.
            let base = domain.hasSuffix("/") ? String(domain.dropLast()) : domain
            let scheme = base.hasPrefix("http") ? "" : "https://"
            let r2KeyRaw =
                entry.r2Key.hasPrefix("/") ? String(entry.r2Key.dropFirst()) : entry.r2Key
            let r2KeyEncoded =
                r2KeyRaw
                .split(separator: "/", omittingEmptySubsequences: false)
                .map {
                    $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
                }
                .joined(separator: "/")
            return "\(scheme)\(base)/\(r2KeyEncoded)"
        }
        // Fall back to stored URL.
        // The stored URL was written by the Rust engine which now percent-encodes
        // path segments, so existing entries may be unencoded. Re-encode to be safe:
        // parse with URLComponents (which handles already-encoded URLs) and
        // reconstruct, falling back to the raw stored value if parsing fails.
        if let components = URLComponents(string: entry.url),
            let host = components.host
        {
            let scheme = components.scheme ?? "https"
            let encodedPath = components.path
                .split(separator: "/", omittingEmptySubsequences: false)
                .map {
                    $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
                }
                .joined(separator: "/")
            return "\(scheme)://\(host)\(encodedPath)"
        }
        return entry.url
    }

    /// Format file size as human-readable string (e.g. "4.2 MB").
    func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Format the uploaded_at timestamp for display.
    func formatDate(_ dateString: String) -> String {
        // SQLite datetime format: "YYYY-MM-DD HH:MM:SS"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = TimeZone(identifier: "UTC")
        guard let date = df.date(from: dateString) else { return dateString }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}
