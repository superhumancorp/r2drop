// R2Drop/App/Onboarding/OnboardingWelcomePanel.swift
// Panel 1: Welcome screen with app icon, headline, and feature pills.
// Shows bounce animation on the icon and three feature highlights.
// Uses larger fonts and generous padding for readability.

import SwiftUI

struct OnboardingWelcomePanel: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconBounce = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App logo with bounce animation
            Image("LogoIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 18))
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

            // Subheadline — larger and more readable
            Text("Upload files to Cloudflare R2\nright from your Finder")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Feature pills — larger text
            HStack(spacing: 12) {
                featurePill("Right-click to upload", icon: "cursorarrow.click")
                featurePill("Blazing fast", icon: "bolt.fill")
                featurePill("Open source", icon: "chevron.left.forwardslash.chevron.right")
            }
            .padding(.top, 4)

            Spacer()

            // Continue button with generous padding
            Button(action: { viewModel.goNext() }) {
                Text("Get Started")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.vertical, 6)
        }
        .padding(36)
    }

    /// A rounded pill showing a feature highlight with readable font.
    private func featurePill(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }
}
