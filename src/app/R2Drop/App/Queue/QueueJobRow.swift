// R2Drop/App/Queue/QueueJobRow.swift
// A single upload job row with liquid glass card and StatusPill badges.
// Shows file name, progress bar, speed, ETA, and action buttons (FR-039).
// Wrapped in a frosted glass container for the Tailscale-style look.

import SwiftUI
import R2Core

struct QueueJobRow: View {
    let job: UploadJob
    let speed: Double
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onBrowse: () -> Void
    let onCopyURL: () -> Void

    @State private var showCancelConfirm = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: file name + status pill + action buttons
            HStack {
                // File icon
                Image(systemName: fileIcon)
                    .font(.title3)
                    .foregroundColor(.accentColor)

                // File name
                Text(fileName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                statusPill
                actionButtons
            }

            // Progress bar (only for active jobs)
            if job.status != .completed && job.status != .failed {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(job.status == .paused ? .yellow : .accentColor)
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

                // Bytes progress for active jobs
                if job.status == .uploading || job.status == .paused {
                    Text("\(formatSize(job.bytesUploaded)) / \(formatSize(job.totalBytes))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .alert("Cancel Upload?", isPresented: $showCancelConfirm) {
            Button("Cancel Upload", role: .destructive) { onCancel() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This will remove \"\(fileName)\" from the upload queue.")
        }
    }

    // MARK: - Status Pill

    @ViewBuilder
    private var statusPill: some View {
        switch job.status {
        case .pending:
            StatusPill(text: "Pending", color: .orange, icon: "clock")
        case .uploading:
            StatusPill(text: "Uploading", color: .blue, icon: "arrow.up.circle.fill")
        case .paused:
            StatusPill(text: "Paused", color: .yellow, icon: "pause.circle.fill")
        case .completed:
            StatusPill(text: "Done", color: .green, icon: "checkmark.circle.fill")
        case .failed:
            StatusPill(text: "Failed", color: .red, icon: "exclamationmark.circle.fill")
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
            if job.status == .completed {
                Button(action: {
                    onCopyURL()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }) {
                    Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                        .font(.caption)
                        .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .help(copied ? "Copied!" : "Copy URL")
            }


            // Browse button — opens R2 dashboard (FR-040)
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

    /// Pick a file icon based on the file extension.
    private var fileIcon: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "film"
        case "mp3", "wav", "aac", "flac":
            return "music.note"
        case "zip", "tar", "gz", "rar":
            return "archivebox"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc.fill"
        }
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
