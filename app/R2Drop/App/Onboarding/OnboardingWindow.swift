// R2Drop/App/Onboarding/OnboardingWindow.swift
// Main onboarding carousel container.
// Hosts panels with slide transitions, dot indicators, and keyboard navigation.
// Supports three modes: initial (5 panels), addAccount (panels 3-5), updateToken (panels 3-5).
// Window is centered, non-resizable, ~600x520pt.
// Uses liquid glass (ultraThinMaterial) with Background-1.png texture.

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
        ZStack {
            // Background-1.png texture with low opacity
            backgroundTexture

            // Liquid glass material overlay
            Rectangle()
                .fill(.ultraThinMaterial)

            // Main content
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

                // Bottom bar: dots centered, back/skip on sides
                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
        }
        .frame(width: 600, height: 520)
        .onChange(of: viewModel.dismissed) { dismissed in
            if dismissed { onDismiss() }
        }
        // Keyboard: Escape to close with confirmation
        .onExitCommand {
            viewModel.skip()
        }
    }

    // MARK: - Background Texture

    /// Subtle background texture from Background-1.png.
    private var backgroundTexture: some View {
        Group {
            if let bgImage = NSImage(named: "Background-1") {
                Image(nsImage: bgImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.08)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
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

    /// Bottom bar with dots perfectly centered using ZStack overlay approach.
    /// Back and Skip buttons sit in the HStack; dots float in an overlay.
    private var bottomBar: some View {
        ZStack {
            // Dots always centered regardless of button widths
            dotIndicators

            // Back and Skip on the sides
            HStack {
                // Back button — only if current panel is not the first for this mode
                if viewModel.currentPanel.rawValue > viewModel.firstPanel.rawValue {
                    Button("Back") {
                        viewModel.goBack()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.callout)
                } else {
                    // Invisible spacer to balance layout
                    Text("Back")
                        .font(.callout)
                        .hidden()
                }

                Spacer()

                // Skip link — only in initial mode on panels 1-3
                if case .initial = viewModel.mode,
                   viewModel.currentPanel.rawValue <= 2 {
                    Button("Skip setup") {
                        viewModel.skip()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.callout)
                } else {
                    // Invisible spacer to keep dots centered
                    Text("Skip setup")
                        .font(.callout)
                        .hidden()
                }
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
