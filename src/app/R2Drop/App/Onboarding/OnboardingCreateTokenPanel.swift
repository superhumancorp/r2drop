// R2Drop/App/Onboarding/OnboardingCreateTokenPanel.swift
// Panel 3: Create Token — guides the user to create a Cloudflare API token.
// "Open Cloudflare Dashboard" button + collapsible step-by-step guide.
// "I already have a token" link skips to Panel 4.

import SwiftUI

struct OnboardingCreateTokenPanel: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showGuide = false

    /// Cloudflare API token creation URL.
    private let cloudflareTokenURL = URL(
        string: "https://dash.cloudflare.com/profile/api-tokens"
    )!

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Create an API Token")
                .font(.title)
                .fontWeight(.bold)

            Text("R2Drop needs a Cloudflare API token with\nR2 read & write permissions.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Open Cloudflare button
            Button(action: { NSWorkspace.shared.open(cloudflareTokenURL) }) {
                Label("Open Cloudflare Dashboard", systemImage: "safari")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Collapsible guide
            DisclosureGroup("Step-by-step guide", isExpanded: $showGuide) {
                VStack(alignment: .leading, spacing: 8) {
                    guideStep("1. Click \"Create Token\"")
                    guideStep("2. Use the \"Edit Cloudflare Workers\" template or create a custom token")
                    guideStep("3. Under Permissions, add \"Account / R2 Storage / Edit\"")
                    guideStep("4. Click \"Continue to summary\" then \"Create Token\"")
                    guideStep("5. Copy the token value shown on screen")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            }
            .padding(.horizontal, 40)

            Spacer()

            // "I already have a token" advances to Panel 4
            Button(action: { viewModel.goNext() }) {
                Text("I already have a token")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }

    private func guideStep(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption2)
                .foregroundColor(.accentColor)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
