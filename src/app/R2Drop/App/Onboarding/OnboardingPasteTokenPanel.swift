// R2Drop/App/Onboarding/OnboardingPasteTokenPanel.swift
// Panel 4: Paste Token — large text field for pasting API token.
// Validates on paste via Cloudflare API. Shows spinner, checkmark, or error.
// Shows confetti emoji when token is valid. Full error codes shown (no truncation).
// Stores valid token in Keychain (FR-002).

import SwiftUI

struct OnboardingPasteTokenPanel: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 20) {
                Spacer()

                // Icon changes to confetti when valid
                if viewModel.tokenValid {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.yellow.gradient)
                } else {
                    Image(systemName: "rectangle.and.paperclip")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                }

                Text("Paste Your Token")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Paste your Cloudflare API token below.\nIt will be stored securely in macOS Keychain.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // Token input field
                tokenField

                // Status indicator — full error text, no truncation
                statusView

                Spacer()

                // Validate button
                Button(action: {
                    Task { await viewModel.validateAndStoreToken() }
                }) {
                    Text("Validate & Continue")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.tokenText.isEmpty || viewModel.isValidatingToken)
                .padding(.vertical, 6)
            }
            .padding(36)

            // Confetti overlay when token is valid
            ConfettiView(isActive: $viewModel.showTokenConfetti)
        }
    }

    // MARK: - Token Field

    private var tokenField: some View {
        HStack {
            SecureField("Paste API token here...", text: $viewModel.tokenText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: 380)
                .disabled(viewModel.isValidatingToken)

            // Validation status icon
            if viewModel.isValidatingToken {
                ProgressView()
                    .controlSize(.small)
            } else if viewModel.tokenValid {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            } else if viewModel.tokenError != nil {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Status

    /// Shows full error text with error codes — no truncation.
    /// Wrapped in a ScrollView so long errors are always readable.
    @ViewBuilder
    private var statusView: some View {
        if let error = viewModel.tokenError {
            VStack(spacing: 10) {
                ScrollView {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 60)

                Button("Clear & Try Again") {
                    viewModel.clearToken()
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 36)
        }
    }
}
