// R2Drop/App/Onboarding/OnboardingCreateTokenPanel.swift
// Panel 3: Create Token — guides the user to create a Cloudflare API token.
// Shows "I already have a token" button at top.
// If user doesn't have one, shows step-by-step guide in a popup sheet.
// "Open Cloudflare Dashboard" button launches the token creation page.

import SwiftUI

struct OnboardingCreateTokenPanel: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showStepByStepSheet = false

    /// Cloudflare API token creation URL.
    private let cloudflareTokenURL = URL(
        string: "https://dash.cloudflare.com/profile/api-tokens"
    )!

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)

            Text("Create an API Token")
                .font(.title)
                .fontWeight(.bold)

            Text("R2Drop needs a Cloudflare API token with\nR2 read & write permissions.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 8)

            // Primary action: "I already have a token" — goes straight to paste
            Button(action: { viewModel.goNext() }) {
                Text("I already have a token")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.vertical, 6)

            // Secondary: open Cloudflare dashboard for token creation
            Button(action: { NSWorkspace.shared.open(cloudflareTokenURL) }) {
                Label("Open Cloudflare Dashboard", systemImage: "safari")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.vertical, 2)

            // Help link: show step-by-step guide in a sheet
            Button("Need help creating a token?") {
                showStepByStepSheet = true
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .font(.callout)

            Spacer()
        }
        .padding(36)
        .sheet(isPresented: $showStepByStepSheet) {
            stepByStepSheet
        }
    }

    // MARK: - Step-by-Step Guide Sheet

    /// Popup sheet with detailed token creation instructions.
    private var stepByStepSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sheet header
            HStack {
                Text("How to Create an API Token")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { showStepByStepSheet = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)

            // Step-by-step guide
            VStack(alignment: .leading, spacing: 12) {
                guideStep(
                    number: 1,
                    text: "Click \"Create Token\" in the Cloudflare dashboard"
                )
                guideStep(
                    number: 2,
                    text: "Select \"Create Custom Token\" at the bottom"
                )
                guideStep(
                    number: 3,
                    text: "Under Permissions, add these three rules:",
                    details: [
                        "Account → R2 Storage → Edit",
                        "Account → Account Settings → Read",
                        "Zone → Zone → Read (optional, for custom domains)"
                    ]
                )
                guideStep(
                    number: 4,
                    text: "Click \"Continue to summary\" then \"Create Token\""
                )
                guideStep(
                    number: 5,
                    text: "Copy the token value shown on screen"
                )
            }

            Spacer()

            // Open Dashboard button inside the sheet
            HStack {
                Spacer()
                Button(action: {
                    NSWorkspace.shared.open(cloudflareTokenURL)
                    showStepByStepSheet = false
                }) {
                    Label("Open Cloudflare Dashboard", systemImage: "safari")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Spacer()
            }
        }
        .padding(28)
        .frame(width: 480, height: 420)
    }

    /// A numbered step with optional detail bullet points.
    private func guideStep(
        number: Int,
        text: String,
        details: [String] = []
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Step number badge
            Text("\(number)")
                .font(.callout)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // Optional detail bullets (e.g., permission rules)
                ForEach(details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundColor(.accentColor)
                        Text(detail)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }
}
