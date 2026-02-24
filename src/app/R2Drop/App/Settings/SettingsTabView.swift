// R2Drop/App/Settings/SettingsTabView.swift
// Settings tab for the Preferences window (US-019).
// Provides controls for app behavior, upload performance, file exclusions,
// CLI installation, hotkey recording, and config directory display.
// All changes persist to ~/.r2drop/config.toml via SettingsViewModel.

import SwiftUI
import R2Core

struct SettingsTabView: View {
    @StateObject private var viewModel = SettingsViewModel()

    // State for the "add pattern" text field
    @State private var newPattern: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                generalSection
                Divider()
                performanceSection
                Divider()
                exclusionSection
                Divider()
                hotkeySection
                Divider()
                cliSection
                Divider()
                configSection
            }
            .padding(20)
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - General Section (FR-045, FR-051)

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)

            Toggle("Hide Dock icon (menu bar only)", isOn: Binding(
                get: { viewModel.hideDockIcon },
                set: { viewModel.toggleHideDockIcon($0) }
            ))

            Toggle("Launch R2Drop at login", isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.toggleLaunchAtLogin($0) }
            ))

            Toggle("Play sound on upload complete", isOn: Binding(
                get: { viewModel.playSound },
                set: { viewModel.togglePlaySound($0) }
            ))

            Toggle("Follow symlinks during upload", isOn: Binding(
                get: { viewModel.followSymlinks },
                set: { viewModel.toggleFollowSymlinks($0) }
            ))
            .help("When off, symbolic links are skipped. When on, symlinks are followed and their targets are uploaded.")
        }
    }

    // MARK: - Upload Performance (FR-048)

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upload Performance")
                .font(.headline)

            // Concurrent uploads: 1-16 (FR-048)
            HStack {
                Text("Concurrent uploads:")
                Stepper(
                    "\(viewModel.concurrentUploads)",
                    value: Binding(
                        get: { viewModel.concurrentUploads },
                        set: { viewModel.updateConcurrentUploads($0) }
                    ),
                    in: 1...16
                )
                .frame(width: 120)
                Spacer()
            }

            // Chunk size: 5-100 MB (FR-048)
            HStack {
                Text("Chunk size:")
                Stepper(
                    "\(viewModel.chunkSizeMb) MB",
                    value: Binding(
                        get: { viewModel.chunkSizeMb },
                        set: { viewModel.updateChunkSize($0) }
                    ),
                    in: 5...100
                )
                .frame(width: 140)
                Spacer()
            }
        }
    }

    // MARK: - File Exclusion Patterns (FR-049)

    private var exclusionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File Exclusion Patterns")
                    .font(.headline)
                Spacer()
                Button("Reset to Defaults") {
                    viewModel.resetExclusionPatterns()
                }
                .controlSize(.small)
            }

            Text("Files matching these patterns are skipped during upload.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Pattern list
            VStack(spacing: 4) {
                ForEach(Array(viewModel.exclusionPatterns.enumerated()), id: \.offset) { index, pattern in
                    HStack {
                        Text(pattern)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: { viewModel.removeExclusionPattern(at: index) }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    if index < viewModel.exclusionPatterns.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)

            // Add pattern row
            HStack {
                TextField("New pattern (e.g. *.tmp)", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addPattern() }
                Button("Add") { addPattern() }
                    .disabled(newPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Global Upload Hotkey (FR-047)

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global Upload Hotkey")
                .font(.headline)

            HStack {
                // Hotkey display field
                Text(viewModel.hotkeyDisplay.isEmpty ? "None" : viewModel.hotkeyDisplay)
                    .frame(minWidth: 120, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(viewModel.isRecordingHotkey
                                    ? Color.accentColor
                                    : Color(nsColor: .separatorColor),
                                    lineWidth: 1)
                    )

                if viewModel.isRecordingHotkey {
                    Button("Cancel") { viewModel.clearHotkey() }
                } else {
                    Button("Record") { viewModel.startRecordingHotkey() }
                    if !viewModel.hotkeyDisplay.isEmpty {
                        Button("Clear") { viewModel.clearHotkey() }
                    }
                }
            }

            Text("Press a key combination while recording to set a global upload shortcut.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - CLI Install (FR-046)

    private var cliSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Command Line Interface")
                .font(.headline)

            HStack {
                if viewModel.cliInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("CLI installed")
                    if !viewModel.cliVersion.isEmpty {
                        Text("(\(viewModel.cliVersion))")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                    Text("CLI not installed")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(viewModel.cliInstalled ? "Reinstall CLI" : "Install CLI") {
                    viewModel.installCLI()
                }
            }

            if !viewModel.cliInstallStatus.isEmpty {
                Text(viewModel.cliInstallStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Installs the r2drop command to /usr/local/bin for terminal usage.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Config Directory (FR-050)

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)

            HStack {
                Text("Config directory:")
                Text(viewModel.configDirPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Open in Finder
                Button(action: { openConfigDir() }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Open in Finder")
            }

            Text("Override with the R2DROP_HOME environment variable.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func addPattern() {
        viewModel.addExclusionPattern(newPattern)
        newPattern = ""
    }

    private func openConfigDir() {
        let url = URL(fileURLWithPath: viewModel.configDirPath)
        NSWorkspace.shared.open(url)
    }
}
