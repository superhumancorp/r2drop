// R2Drop/App/Queue/QueueTabView.swift
// Main Queue tab for the Preferences window (FR-037, FR-038).
// Shows an aggregate status bar at top and a scrollable list of upload jobs.
// Each job shows progress, speed, and pause/resume/cancel controls (FR-039).
// "Browse" button per job opens the Cloudflare R2 dashboard (FR-040).

import SwiftUI
import R2Core

struct QueueTabView: View {
    @StateObject private var viewModel = QueueViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Aggregate status bar (FR-038)
            aggregateBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Job list or empty state
            if viewModel.jobs.isEmpty {
                emptyState
            } else {
                jobList
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Aggregate Status Bar (FR-038)

    private var aggregateBar: some View {
        HStack {
            // "Files X of Y" progress
            Text("Files \(viewModel.completedCount) of \(viewModel.totalCount)")
                .font(.headline)

            Spacer()

            // Average upload rate (only when actively uploading)
            if viewModel.hasActiveUploads {
                let speed = viewModel.aggregateSpeed
                if speed > 0 {
                    Image(systemName: "arrow.up")
                        .foregroundColor(.blue)
                    Text(formatSpeed(speed))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Job List (FR-037)

    private var jobList: some View {
        List {
            ForEach(viewModel.jobs) { job in
                QueueJobRow(
                    job: job,
                    speed: viewModel.speed(for: job),
                    onPause: { viewModel.pauseJob(job) },
                    onResume: { viewModel.resumeJob(job) },
                    onCancel: { viewModel.cancelJob(job) },
                    onBrowse: { openBrowse(for: job) }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No uploads in queue")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Right-click files in Finder or drag them onto the menu bar icon to upload.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// Open the Cloudflare R2 dashboard for a job's bucket (FR-040).
    private func openBrowse(for job: UploadJob) {
        guard let url = viewModel.browseURL(for: job) else { return }
        NSWorkspace.shared.open(url)
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatted = ByteCountFormatter.string(
            fromByteCount: Int64(bytesPerSecond), countStyle: .file
        )
        return "\(formatted)/s"
    }
}
