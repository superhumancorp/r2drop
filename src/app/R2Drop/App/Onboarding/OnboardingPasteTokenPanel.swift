// R2Drop/App/Onboarding/OnboardingPasteTokenPanel.swift
// Panel 4: Paste Token — large text field for pasting API token.
// Validates on paste via Cloudflare API. Shows spinner, checkmark, or error.
// Stores valid token in Keychain (FR-002).

import SwiftUI

struct OnboardingPasteTokenPanel: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "rectangle.and.paperclip")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Paste Your Token")
                .font(.title)
                .fontWeight(.bold)

            Text("Paste your Cloudflare API token below.\nIt will be stored securely in macOS Keychain.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Token input field
            tokenField

            // Status indicator
            statusView

            Spacer()

            // Validate button
            Button(action: {
                Task { await viewModel.validateAndStoreToken() }
            }) {
                Text("Validate & Continue")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.tokenText.isEmpty || viewModel.isValidatingToken)
        }
        .padding(32)
    }

    // MARK: - Token Field

    private var tokenField: some View {
        HStack {
            SecureField("Paste API token here...", text: $viewModel.tokenText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: 360)
                .disabled(viewModel.isValidatingToken)

            // Validation status icon
            if viewModel.isValidatingToken {
                ProgressView()
                    .controlSize(.small)
            } else if viewModel.tokenValid {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if viewModel.tokenError != nil {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusView: some View {
        if let error = viewModel.tokenError {
            VStack(spacing: 8) {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)

                Button("Clear & Try Again") {
                    viewModel.clearToken()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 40)
        }
    }
}
