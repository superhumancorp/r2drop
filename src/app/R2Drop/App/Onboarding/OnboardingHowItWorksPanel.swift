// R2Drop/App/Onboarding/OnboardingHowItWorksPanel.swift
// Panel 2: How It Works — 3 vertically stacked steps explaining the workflow.
// Right-click → Upload → Clipboard flow with icons and descriptions.

import SwiftUI

struct OnboardingHowItWorksPanel: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("How It Works")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 20) {
                stepRow(
                    number: 1,
                    icon: "cursorarrow.click.2",
                    title: "Right-click in Finder",
                    description: "Select any file or folder, right-click, and choose \"Send to R2\"."
                )

                stepRow(
                    number: 2,
                    icon: "arrow.up.circle",
                    title: "Fast parallel upload",
                    description: "R2Drop splits large files into chunks and uploads them in parallel."
                )

                stepRow(
                    number: 3,
                    icon: "doc.on.clipboard",
                    title: "URL copied to clipboard",
                    description: "When the upload finishes, the public URL is copied automatically."
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: { viewModel.goNext() }) {
                Text("Continue")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.bottom, 48)
        .padding(.horizontal, 32)
    }

    /// A single step row with a numbered circle, icon, title, and description.
    private func stepRow(
        number: Int,
        icon: String,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number + icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(number). \(title)")
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
