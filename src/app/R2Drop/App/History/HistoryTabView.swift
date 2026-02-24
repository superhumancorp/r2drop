// R2Drop/App/History/HistoryTabView.swift
// History tab for the Preferences window (US-020, FR-052 through FR-054).
// Searchable, scrollable list of completed uploads sorted most recent first.
// Each row shows file name, size, timestamp, and a "Copy URL" button (FR-053).
// "Clear History" button removes all entries (FR-054).

import SwiftUI
import R2Core

struct HistoryTabView: View {
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Search bar and clear button
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Entry list or empty state
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Search field (FR-052)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search by file name...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: viewModel.searchText) { _ in
                        viewModel.load()
                    }
                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                        viewModel.load()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: .controlColor))
            .cornerRadius(6)

            // Clear History button (FR-054)
            Button("Clear History") {
                confirmClearHistory()
            }
            .disabled(viewModel.entries.isEmpty)
        }
    }

    // MARK: - Entry List

    private var entryList: some View {
        List {
            ForEach(viewModel.entries) { entry in
                HistoryRow(entry: entry, viewModel: viewModel)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(viewModel.searchText.isEmpty
                 ? "No upload history"
                 : "No results for \"\(viewModel.searchText)\"")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(viewModel.searchText.isEmpty
                 ? "Completed uploads will appear here."
                 : "Try a different search term.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Show confirmation alert before clearing all history.
    private func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Upload History?"
        alert.informativeText = "This will permanently remove all history entries. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.clearHistory()
        }
    }
}

// MARK: - HistoryRow

/// A single row in the history list showing file info and a Copy URL button.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let viewModel: HistoryViewModel

    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundColor(.accentColor)

            // File details
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(viewModel.formatSize(entry.fileSize))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(viewModel.formatDate(entry.uploadedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(entry.bucket)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .controlColor))
                        .cornerRadius(3)
                }
            }

            Spacer()

            // Copy URL button (FR-053)
            Button(action: {
                viewModel.copyURL(for: entry)
                showCopiedFeedback()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : "Copy URL")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    /// Brief "Copied" feedback, reverts after 1.5 seconds.
    private func showCopiedFeedback() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
