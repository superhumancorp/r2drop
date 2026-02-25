// R2Drop/App/Settings/SettingsTabView.swift
// Settings tab with liquid glass card sections (US-019).
// Each settings group (General, Performance, Exclusions, Hotkey, CLI, Config)
// is wrapped in a GlassCard. Toggles use GlassToggleRow for consistent styling.
// All changes persist to ~/.r2drop/config.toml via SettingsViewModel.

import SwiftUI
import R2Core

struct SettingsTabView: View {
    @StateObject private var viewModel = SettingsViewModel()

    // State for the "add pattern" text field
    @State private var newPattern: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                generalCard
                performanceCard
                exclusionCard
                cliCard
                configCard
            }
            .padding(20)
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - General Section (FR-045, FR-051)

    private var generalCard: some View {
        GlassCard {
            GlassSectionHeader(
                title: "General",
                systemImage: "gearshape"
            )

            GlassToggleRow(
                title: "Hide Dock icon (menu bar only)",
                isOn: Binding(
                    get: { viewModel.hideDockIcon },
                    set: { viewModel.toggleHideDockIcon($0) }
                )
            )

            Divider().opacity(0.3)

            GlassToggleRow(
                title: "Launch R2Drop at login",
                isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.toggleLaunchAtLogin($0) }
                )
            )

            Divider().opacity(0.3)

            GlassToggleRow(
                title: "Play sound on upload complete",
                isOn: Binding(
                    get: { viewModel.playSound },
                    set: { viewModel.togglePlaySound($0) }
                )
            )

            Divider().opacity(0.3)

            GlassToggleRow(
                title: "Follow symlinks during upload",
                subtitle: "When off, symbolic links are skipped. When on, targets are uploaded.",
                isOn: Binding(
                    get: { viewModel.followSymlinks },
                    set: { viewModel.toggleFollowSymlinks($0) }
                )
            )
        }
    }

    // MARK: - Upload Performance (FR-048)

    private var performanceCard: some View {
        GlassCard {
            GlassSectionHeader(
                title: "Upload Performance",
                systemImage: "speedometer"
            )

            // Concurrent uploads: 1-16
            HStack {
                Text("Concurrent uploads:")
                    .font(.body)
                Spacer()
                Stepper(
                    "\(viewModel.concurrentUploads)",
                    value: Binding(
                        get: { viewModel.concurrentUploads },
                        set: { viewModel.updateConcurrentUploads($0) }
                    ),
                    in: 1...16
                )
                .frame(width: 120)
            }

            Divider().opacity(0.3)

            // Chunk size: 5-100 MB
            HStack {
                Text("Chunk size:")
                    .font(.body)
                Spacer()
                Stepper(
                    "\(viewModel.chunkSizeMb) MB",
                    value: Binding(
                        get: { viewModel.chunkSizeMb },
                        set: { viewModel.updateChunkSize($0) }
                    ),
                    in: 5...100
                )
                .frame(width: 140)
            }
        }
    }

    // MARK: - File Exclusion Patterns (FR-049)

    private var exclusionCard: some View {
        GlassCard {
            HStack {
                GlassSectionHeader(
                    title: "File Exclusion Patterns",
                    systemImage: "eye.slash"
                )
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
                        Divider().opacity(0.2)
                    }
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

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
    // MARK: - CLI Install (FR-046)

    private var cliCard: some View {
        GlassCard {
            GlassSectionHeader(
                title: "Command Line Interface",
                systemImage: "terminal"
            )

            HStack {
                if viewModel.cliInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("CLI installed")
                        .font(.body)
                    if !viewModel.cliVersion.isEmpty {
                        Text("(\(viewModel.cliVersion))")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                } else {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                    Text("CLI not installed")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(viewModel.cliInstalled ? "Reinstall CLI" : "Install CLI") {
                    viewModel.installCLI()
                }
                .buttonStyle(.bordered)
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

    private var configCard: some View {
        GlassCard {
            GlassSectionHeader(
                title: "Configuration",
                systemImage: "folder.badge.gearshape"
            )

            HStack {
                Text("Config directory:")
                    .font(.body)
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
