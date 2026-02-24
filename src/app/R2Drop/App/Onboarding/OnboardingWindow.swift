// R2Drop/App/Onboarding/OnboardingWindow.swift
// Main onboarding carousel container.
// Hosts panels with slide transitions, dot indicators, and keyboard navigation.
// Supports three modes: initial (5 panels), addAccount (panels 3-5), updateToken (panels 3-5).
// Window is centered, non-resizable, ~520x400pt (FR-015).

import SwiftUI

/// The onboarding carousel view. Shown on first launch, add account, or update token.
struct OnboardingWindow: View {
    @StateObject private var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called when onboarding completes or is skipped.
    var onDismiss: () -> Void = {}

    /// Create the onboarding window with the given mode.
    /// - `.initial`: full 5-panel flow (first launch)
    /// - `.addAccount`: panels 3-5 (FR-007)
    /// - `.updateToken(name)`: panels 3-5 for existing account (FR-008)
    init(mode: OnboardingMode = .initial, onDismiss: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(mode: mode))
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            // Panel content area with slide transition
            ZStack {
                panelView
                    .id(viewModel.currentPanel)
                    .transition(slideTransition)
            }
            .animation(
                reduceMotion ? .none : .easeInOut(duration: 0.25),
                value: viewModel.currentPanel
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom bar: dots + navigation buttons
            bottomBar
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .frame(width: 520, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: viewModel.dismissed) { dismissed in
            if dismissed { onDismiss() }
        }
        // Keyboard: Escape to close with confirmation
        .onExitCommand {
            viewModel.skip()
        }
    }

    // MARK: - Panel Router

    @ViewBuilder
    private var panelView: some View {
        switch viewModel.currentPanel {
        case .welcome:
            OnboardingWelcomePanel(viewModel: viewModel)
        case .howItWorks:
            OnboardingHowItWorksPanel(viewModel: viewModel)
        case .createToken:
            OnboardingCreateTokenPanel(viewModel: viewModel)
        case .pasteToken:
            OnboardingPasteTokenPanel(viewModel: viewModel)
        case .chooseBucket:
            OnboardingChooseBucketPanel(viewModel: viewModel)
        }
    }

    // MARK: - Slide Transition

    /// Left-to-right slide; respects reduceMotion.
    private var slideTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Back button — only if current panel is not the first for this mode
            if viewModel.currentPanel.rawValue > viewModel.firstPanel.rawValue {
                Button("Back") {
                    viewModel.goBack()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Dot indicators — only show panels visible in this mode
            dotIndicators

            Spacer()

            // Skip link — only in initial mode on panels 1-3
            if case .initial = viewModel.mode,
               viewModel.currentPanel.rawValue <= 2 {
                Button("Skip setup") {
                    viewModel.skip()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)
            } else {
                // Invisible spacer to keep dots centered
                Text("Skip setup")
                    .font(.caption)
                    .hidden()
            }
        }
    }

    private var dotIndicators: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.visiblePanels, id: \.rawValue) { panel in
                Circle()
                    .fill(panel == viewModel.currentPanel
                          ? Color.accentColor
                          : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
