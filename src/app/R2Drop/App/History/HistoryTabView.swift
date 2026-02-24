// R2Drop/App/History/HistoryTabView.swift
// History tab with liquid glass styling (US-020, FR-052 through FR-054).
// GlassSearchBar in the frosted header. Scrollable list of completed uploads.
// Each row shows file name, size, timestamp, and "Copy URL" button (FR-053).
// "Clear History" button removes all entries (FR-054).

import SwiftUI
import R2Core

struct HistoryTabView: View {
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Search bar and clear button — frosted glass toolbar
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial)

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
            // Search field (FR-052) — glass search bar
            GlassSearchBar(
                text: $viewModel.searchText,
                placeholder: "Search by file name...",
                onClear: { viewModel.load() }
            )
            .onChange(of: viewModel.searchText) { _ in
                viewModel.load()
            }

            // Clear History button (FR-054)
            Button("Clear History") {
                confirmClearHistory()
            }
            .disabled(viewModel.entries.isEmpty)
        }
    }

    // MARK: - Entry List

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(viewModel.entries) { entry in
                    HistoryRow(entry: entry, viewModel: viewModel)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        GlassEmptyState(
            icon: "clock",
            title: viewModel.searchText.isEmpty
                ? "No upload history"
                : "No results for \"\(viewModel.searchText)\"",
            subtitle: viewModel.searchText.isEmpty
                ? "Completed uploads will appear here."
                : "Try a different search term."
        )
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

/// A single row in the history list with liquid glass card styling.
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

                    // Bucket badge
                    Text(entry.bucket)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
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
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    /// Brief "Copied" feedback, reverts after 1.5 seconds.
    private func showCopiedFeedback() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
