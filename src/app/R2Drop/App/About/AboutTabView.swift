// R2Drop/App/About/AboutTabView.swift
// About tab with liquid glass card sections (US-021, FR-055 through FR-058).
// Hero1.png banner scales with window width. App info, links, copyright,
// and Sparkle auto-update controls each in their own GlassCard.

import SwiftUI

struct AboutTabView: View {
    @StateObject private var viewModel = AboutViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero1.png banner — scales width with window
                heroBanner

                VStack(spacing: 16) {
                    // Website link at top
                    websiteCard

                    // App icon + title + version (FR-055)
                    appInfoCard

                    // Developer info
                    developerCard

                    // Links: Privacy, Terms, Report Issue (FR-056)
                    linksCard

                    // Copyright & trademark (FR-057)
                    copyrightCard

                    // Auto-update controls (FR-058)
                    updateCard
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hero Banner

    /// Hero1.png as a full-width banner that scales with the window.
    private var heroBanner: some View {
        Group {
            if let heroImage = NSImage(named: "Hero1") {
                Image(nsImage: heroImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipped()
            } else {
                // Fallback gradient if image not found
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 160)
            }
        }
    }

    // MARK: - Website Link

    private var websiteCard: some View {
        GlassCard(spacing: 0) {
            linkRow(title: "r2drop.com", icon: "globe") {
                viewModel.openWebsite()
            }
        }
    }

    // MARK: - Developer Info

    private var developerCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                Text("Developed by Paul Pierre")
                    .font(.callout)
                    .foregroundColor(.secondary)

                Spacer()

                // X (Twitter) link
                Button(action: { viewModel.openDeveloperX() }) {
                    Image(systemName: "link")
                        .font(.body)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("@paulpierre on X")

                // GitHub link
                Button(action: { viewModel.openDeveloperGitHub() }) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.body)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("paulpierre on GitHub")
            }
        }
    }

    // MARK: - App Info (FR-055)

    private var appInfoCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                // App icon
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("R2Drop for macOS")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Version \(viewModel.appVersion) (\(viewModel.buildNumber))")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Links (FR-056)

    private var linksCard: some View {
        GlassCard(spacing: 0) {
            linkRow(title: "Privacy Policy", icon: "lock.shield") {
                viewModel.openPrivacyPolicy()
            }
            Divider().opacity(0.3)
            linkRow(title: "Terms of Service", icon: "doc.text") {
                viewModel.openTermsOfService()
            }
            Divider().opacity(0.3)
            linkRow(title: "Report an Issue", icon: "exclamationmark.bubble") {
                viewModel.openReportIssue()
            }
        }
    }

    /// A single link row — icon, title, chevron.
    private func linkRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Copyright (FR-057)

    private var copyrightCard: some View {
        GlassCard {
            VStack(spacing: 4) {
                Text("\u{00A9} 2026 Superhuman Corp. All rights reserved.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                Text("R2Drop is a trademark of Superhuman Corp.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Update Controls (FR-058)

    private var updateCard: some View {
        GlassCard {
            GlassSectionHeader(
                title: "Updates",
                systemImage: "arrow.triangle.2.circlepath"
            )

            // Auto-check toggle
            GlassToggleRow(
                title: "Automatically check for updates",
                isOn: Binding(
                    get: { viewModel.automaticallyChecksForUpdates },
                    set: { viewModel.toggleAutoCheck($0) }
                )
            )

            Divider().opacity(0.3)

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
                .buttonStyle(.bordered)
                .disabled(!viewModel.canCheckForUpdates || viewModel.isCheckingForUpdates)

                Text("Last checked: \(viewModel.lastCheckDateString)")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
}
