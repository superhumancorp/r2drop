// R2Drop/App/About/AboutTabView.swift
// About tab for the Preferences window (US-021, FR-055 through FR-058).
// Shows app info, version, links, copyright, and Sparkle auto-update controls.

import SwiftUI

struct AboutTabView: View {
    @StateObject private var viewModel = AboutViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon + title + version (FR-055)
            appInfoSection

            Spacer().frame(height: 24)

            // Links: Privacy, Terms, Report Issue (FR-056)
            linksSection

            Spacer().frame(height: 20)

            // Copyright & trademark (FR-057)
            copyrightSection

            Spacer().frame(height: 24)

            Divider()
                .padding(.horizontal, 40)

            Spacer().frame(height: 20)

            // Auto-update controls (FR-058)
            updateSection

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: - App Info (FR-055)

    private var appInfoSection: some View {
        VStack(spacing: 8) {
            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("R2Drop for macOS")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version \(viewModel.appVersion) (\(viewModel.buildNumber))")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Links (FR-056)

    private var linksSection: some View {
        HStack(spacing: 16) {
            Button("Privacy Policy") { viewModel.openPrivacyPolicy() }
                .buttonStyle(.link)

            Text("|")
                .foregroundColor(.secondary)

            Button("Terms of Service") { viewModel.openTermsOfService() }
                .buttonStyle(.link)

            Text("|")
                .foregroundColor(.secondary)

            Button("Report an Issue") { viewModel.openReportIssue() }
                .buttonStyle(.link)
        }
        .font(.caption)
    }

    // MARK: - Copyright (FR-057)

    private var copyrightSection: some View {
        VStack(spacing: 4) {
            Text("\u{00A9} 2026 Superhuman Corp. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("R2Drop is a trademark of Superhuman Corp.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Update Controls (FR-058)

    private var updateSection: some View {
        VStack(spacing: 12) {
            // Auto-check toggle
            Toggle("Automatically check for updates", isOn: Binding(
                get: { viewModel.automaticallyChecksForUpdates },
                set: { viewModel.toggleAutoCheck($0) }
            ))
            .toggleStyle(.checkbox)

            // Check Now button + last checked timestamp
            HStack(spacing: 12) {
                Button(action: { viewModel.checkForUpdates() }) {
                    if viewModel.isCheckingForUpdates {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking...")
                        }
                    } else {
                        Text("Check Now")
                    }
                }
                .disabled(!viewModel.canCheckForUpdates || viewModel.isCheckingForUpdates)

                Text("Last checked: \(viewModel.lastCheckDateString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
