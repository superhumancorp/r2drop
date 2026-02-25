// R2Drop/App/Onboarding/OnboardingChooseBucketPanel.swift
// Panel 5: Choose Bucket — dropdown of buckets, create new bucket form,
// default upload path, custom domain dropdown (fetched from API), and "Done" button.
// Shows Hero4.png banner + ConfettiSwiftUI animation + bell sound on completion.
// Hero4 starts zoomed out and slowly zooms in for a cinematic effect.

import SwiftUI
import ConfettiSwiftUI

struct OnboardingChooseBucketPanel: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Trigger for ConfettiSwiftUI — increment to fire confetti.
    @State private var confettiTrigger = 0

    /// Controls the Hero4 zoom animation (starts zoomed out, animates to full).
    @State private var heroScale: CGFloat = 0.85

    var body: some View {
        ZStack {
            // Main content
            if viewModel.showCelebration {
                celebrationView
            } else {
                mainContent
            }
        }
        // Fire ConfettiSwiftUI when celebration starts
        .confettiCannon(
            trigger: $confettiTrigger,
            num: 40,
            confettis: [.shape(.circle), .shape(.triangle), .shape(.square), .text("🎉"), .text("✨")],
            colors: [.blue, .cyan, .purple, .yellow, .orange, .pink],
            confettiSize: 12.0,
            rainHeight: 500.0,
            fadesOut: true,
            openingAngle: .degrees(40),
            closingAngle: .degrees(140),
            radius: 280,
            repetitions: 3,
            repetitionInterval: 0.8
        )
        .onChange(of: viewModel.showFinalConfetti) { showConfetti in
            if showConfetti {
                confettiTrigger += 1
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer().frame(height: 8)

                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)

                Text("Choose a Bucket")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Select which R2 bucket to upload files to.")
                    .font(.title3)
                    .foregroundColor(.secondary)

                // Bucket picker
                bucketPicker

                // Create new bucket toggle
                createBucketSection

                // Default path
                HStack {
                    Text("Default path:")
                        .font(.body)
                    TextField("/", text: $viewModel.defaultPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                }
                .padding(.horizontal, 48)

                // Custom domain dropdown (fetched from API)
                customDomainSection

                Spacer().frame(height: 4)

                // Done button
                Button(action: {
                    Task { await viewModel.finishSetup() }
                }) {
                    Text("Done")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.selectedBucket.isEmpty)
                .padding(.vertical, 6)

                Spacer().frame(height: 16)
            }
            .padding(.horizontal, 36)
        }
    }

    // MARK: - Bucket Picker

    private var bucketPicker: some View {
        Picker("Bucket", selection: $viewModel.selectedBucket) {
            if viewModel.buckets.isEmpty {
                Text("No buckets found").tag("")
            }
            ForEach(viewModel.buckets, id: \.self) { bucket in
                Text(bucket).tag(bucket)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 320)
        .onChange(of: viewModel.selectedBucket) { newBucket in
            // Fetch custom domains when bucket changes
            if !newBucket.isEmpty {
                Task { await viewModel.fetchCustomDomains(bucket: newBucket) }
            }
        }
    }

    // MARK: - Create Bucket

    private var createBucketSection: some View {
        VStack(spacing: 8) {
            if viewModel.showCreateBucket {
                HStack(spacing: 8) {
                    TextField("new-bucket-name", text: $viewModel.newBucketName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)

                    Button(action: {
                        Task { await viewModel.createNewBucket() }
                    }) {
                        if viewModel.isCreatingBucket {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(viewModel.newBucketName.isEmpty || viewModel.isCreatingBucket)

                    Button("Cancel") {
                        viewModel.showCreateBucket = false
                        viewModel.newBucketName = ""
                        viewModel.bucketError = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                if let error = viewModel.bucketError {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                }
            } else {
                Button("Create New Bucket") {
                    viewModel.showCreateBucket = true
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.body)
            }
        }
    }

    // MARK: - Custom Domain

    /// Custom domain picker — always a dropdown. "Default (R2 URL)" first,
    /// then any active custom domains fetched from Cloudflare API.
    private var customDomainSection: some View {
        HStack {
            Text("Custom domain:")
                .font(.body)

            if viewModel.isLoadingDomains {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading domains...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                // Always show Picker — "Default" first, plus any fetched domains.
                Picker("", selection: $viewModel.customDomain) {
                    Text("Default (R2 URL)").tag("")
                    ForEach(viewModel.customDomains, id: \.self) { domain in
                        Text(domain).tag(domain)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Celebration View

    /// Final celebration screen with Hero4.png banner, success message, and confetti.
    /// Hero4 starts zoomed out (0.85x) and slowly zooms to full scale.
    private var celebrationView: some View {
        VStack(spacing: 16) {
            // Hero4.png banner — starts zoomed out, animates in
            heroBanner

            Spacer().frame(height: 8)

            Text("You're all set!")
                .font(.title)
                .fontWeight(.bold)

            Text("R2Drop is ready to upload files.")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer().frame(height: 4)

            // User must click Done to dismiss — no auto-dismiss.
            Button(action: { viewModel.skip() }) {
                Text("Done")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.vertical, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            // Animate Hero4 from zoomed-out to full scale over 4 seconds
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 4.0)) {
                    heroScale = 1.15
                }
            } else {
                heroScale = 1.0
            }
        }
    }

    /// Hero4.png as a cover banner with slow zoom-in animation.
    private var heroBanner: some View {
        Group {
            if let heroImage = NSImage(named: "Hero4") {
                Image(nsImage: heroImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .scaleEffect(heroScale)
                    .clipped()
            } else {
                // Fallback if image not found
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.yellow.gradient)
                    .frame(height: 220)
            }
        }
    }
}
