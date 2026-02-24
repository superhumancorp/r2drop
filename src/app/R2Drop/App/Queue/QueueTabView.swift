// R2Drop/App/Queue/QueueTabView.swift
// Queue tab with liquid glass styling (FR-037, FR-038).
// Aggregate status bar in a frosted glass header. Scrollable job list below.
// Each job shows progress, speed, and controls (FR-039).
// Empty state uses GlassEmptyState component.

import SwiftUI
import R2Core

struct QueueTabView: View {
    @StateObject private var viewModel = QueueViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Aggregate status bar (FR-038) — frosted glass header
            aggregateBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.thinMaterial)

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
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.accentColor)
                        Text(formatSpeed(speed))
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Job List (FR-037)

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
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
            .padding(16)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        GlassEmptyState(
            icon: "tray",
            title: "No uploads in queue",
            subtitle: "Right-click files in Finder or drag them onto the menu bar icon to upload."
        )
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
