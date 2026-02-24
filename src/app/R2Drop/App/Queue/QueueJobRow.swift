// R2Drop/App/Queue/QueueJobRow.swift
// A single row in the upload queue list.
// Shows file name, size, progress bar, speed, status badge, and action buttons.
// Pause/Resume/Cancel buttons per job (FR-039).

import SwiftUI
import R2Core

struct QueueJobRow: View {
    let job: UploadJob
    let speed: Double
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onBrowse: () -> Void

    @State private var showCancelConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: file name + status badge + action buttons
            HStack {
                // File name (just the last path component)
                Text(fileName)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                statusBadge
                actionButtons
            }

            // Progress bar (only for uploading/paused/pending jobs)
            if job.status != .completed && job.status != .failed {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
            }

            // Bottom row: size + speed/ETA or error message
            HStack {
                Text(formatSize(job.totalBytes))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if job.status == .uploading && speed > 0 {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text("\(formatSpeed(speed))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let eta = estimatedTimeRemaining {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(eta)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if job.status == .completed {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text("Done")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if job.status == .failed, let error = job.errorMessage {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }

                Spacer()

                // Bytes progress for uploading jobs
                if job.status == .uploading || job.status == .paused {
                    Text("\(formatSize(job.bytesUploaded)) / \(formatSize(job.totalBytes))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Cancel Upload?", isPresented: $showCancelConfirm) {
            Button("Cancel Upload", role: .destructive) { onCancel() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This will remove \"\(fileName)\" from the upload queue.")
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch job.status {
        case .pending:
            Label("Pending", systemImage: "clock")
                .font(.caption)
                .foregroundColor(.orange)
        case .uploading:
            Label("Uploading", systemImage: "arrow.up.circle.fill")
                .font(.caption)
                .foregroundColor(.blue)
        case .paused:
            Label("Paused", systemImage: "pause.circle.fill")
                .font(.caption)
                .foregroundColor(.yellow)
        case .completed:
            Label("Completed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    // MARK: - Action Buttons (FR-039)

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            if job.status == .uploading || job.status == .pending {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Pause")
            }

            if job.status == .paused || job.status == .failed {
                Button(action: onResume) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Resume")
            }

            if job.status != .completed {
                Button(action: { showCancelConfirm = true }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            }

            // Browse button — opens R2 dashboard for this bucket (FR-040)
            Button(action: onBrowse) {
                Image(systemName: "safari")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Open in Cloudflare Dashboard")
        }
    }

    // MARK: - Helpers

    private var fileName: String {
        (job.filePath as NSString).lastPathComponent
    }

    private var estimatedTimeRemaining: String? {
        guard speed > 0, job.totalBytes > job.bytesUploaded else { return nil }
        let remaining = Double(job.totalBytes - job.bytesUploaded) / speed
        if remaining < 60 {
            return "\(Int(remaining))s left"
        } else if remaining < 3600 {
            return "\(Int(remaining / 60))m left"
        } else {
            return "\(Int(remaining / 3600))h left"
        }
    }

    private func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatted = ByteCountFormatter.string(
            fromByteCount: Int64(bytesPerSecond), countStyle: .file
        )
        return "\(formatted)/s"
    }
}
