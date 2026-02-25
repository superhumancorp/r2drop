// R2Drop/App/Queue/QueueTabView.swift
// Uploads tab with liquid glass styling (FR-037, FR-038).
// Aggregate status bar in a frosted glass header. Scrollable job list below.
// Each job shows progress, speed, and controls (FR-039).
// Supports drag-and-drop file uploads directly into the tab.
// Empty state uses GlassEmptyState component with drag-drop target.
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
        VStack(spacing: 16) {
            GlassEmptyState(
                icon: "arrow.up.circle",
                title: "No uploads in queue",
                subtitle: "Drag files here, right-click in Finder, or drop them on the menu bar icon."
            )

            // Drag-and-drop target area
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(.secondary.opacity(0.4))
                .frame(height: 100)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Drop files to upload")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers)
                    return true
                }
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// Handle files dropped onto the uploads tab.
    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    self.viewModel.queueDroppedFile(url)
                }
            }
        }
    }

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
