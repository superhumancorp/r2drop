// R2Drop/App/Queue/QueueTabView.swift
// Uploads tab with liquid glass styling (FR-037, FR-038).
// Aggregate status bar in a frosted glass header with status indicator.
// Scrollable job list below with improved spacing and hover animations.
// Supports drag-and-drop file uploads with visual feedback.
// Empty state uses GlassEmptyState component with unified drag-drop target.
import SwiftUI
import R2Core

struct QueueTabView: View {
    @StateObject private var viewModel = QueueViewModel()

    /// Tracks whether user is hovering a file over the drop zone.
    @State private var isDropTargeted = false

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
        // Full-view drop target for when jobs exist
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    // MARK: - Aggregate Status Bar (FR-038)

    private var aggregateBar: some View {
        HStack {
            // "Files X of Y" progress
            Text("Files \(viewModel.completedCount) of \(viewModel.totalCount)")
                .font(.headline)

            Spacer()

            // Status label — subtle indicator of what's happening
            statusLabel
                .font(.callout)
                .foregroundColor(.secondary)

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

    /// Status label showing current queue state.
    @ViewBuilder
    private var statusLabel: some View {
        let uploading = viewModel.jobs.filter { $0.status == .uploading }.count
        let pending = viewModel.jobs.filter { $0.status == .pending }.count
        let paused = viewModel.jobs.filter { $0.status == .paused }.count
        let failed = viewModel.jobs.filter { $0.status == .failed }.count

        if uploading > 0 {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Uploading \(uploading) file\(uploading == 1 ? "" : "s")...")
            }
        } else if pending > 0 {
            Text("Waiting...")
        } else if paused > 0 && failed == 0 {
            Text("All paused")
        } else if failed > 0 {
            Text("\(failed) failed")
                .foregroundColor(.red)
        } else if viewModel.jobs.isEmpty {
            Text("Idle")
        } else {
            Text("Complete")
                .foregroundColor(.green)
        }
    }

    // MARK: - Job List (FR-037)

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.jobs) { job in
                    QueueJobRow(
                        job: job,
                        speed: viewModel.speed(for: job),
                        onPause: { viewModel.pauseJob(job) },
                        onResume: { viewModel.resumeJob(job) },
                        onCancel: { viewModel.cancelJob(job) },
                        onBrowse: { openBrowse(for: job) },
                        onCopyURL: { viewModel.copyURL(for: job) }
                    )
                }
            }
            .padding(20)
        }
        // Visual feedback when dragging files over the job list
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isDropTargeted ? 0.6 : 0), lineWidth: 2)
                .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            // Unified empty state with integrated drop zone
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "arrow.up.circle")
                    .font(.system(size: 48))
                    .foregroundColor(isDropTargeted ? .accentColor : .secondary.opacity(0.5))
                    .scaleEffect(isDropTargeted ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isDropTargeted)

                Text(isDropTargeted ? "Drop to upload" : "No uploads in queue")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(isDropTargeted ? .primary : .secondary)
                    .animation(.easeInOut(duration: 0.15), value: isDropTargeted)

                Text("Drag files here, right-click in Finder, or drop them on the menu bar icon.")
                    .font(.callout)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.15),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.5, dash: isDropTargeted ? [] : [10])
                    )
                    .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
            )
            .padding(20)
        }
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
