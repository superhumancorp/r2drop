// R2Drop/App/Onboarding/OnboardingWelcomePanel.swift
// Panel 1: Welcome screen with app icon, headline, and feature pills.
// Shows bounce animation on the icon and three feature highlights.

import SwiftUI

struct OnboardingWelcomePanel: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconBounce = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App logo with bounce animation
            Image("LogoIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .offset(y: iconBounce ? -6 : 0)
                .animation(
                    reduceMotion ? .none :
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: iconBounce
                )
                .onAppear {
                    iconBounce = true
                }

            // Headline
            Text("R2Drop")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Subheadline
            Text("Upload files to Cloudflare R2\nright from your Finder")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Feature pills
            HStack(spacing: 12) {
                featurePill("Right-click to upload", icon: "cursorarrow.click")
                featurePill("Blazing fast", icon: "bolt.fill")
                featurePill("Open source", icon: "chevron.left.forwardslash.chevron.right")
            }
            .padding(.top, 8)

            Spacer()

            // Continue button
            Button(action: { viewModel.goNext() }) {
                Text("Get Started")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }

    /// A rounded pill showing a feature highlight.
    private func featurePill(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }
}
