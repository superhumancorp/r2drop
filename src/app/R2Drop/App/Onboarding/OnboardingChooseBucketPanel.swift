// R2Drop/App/Onboarding/OnboardingChooseBucketPanel.swift
// Panel 5: Choose Bucket — dropdown of buckets, create new bucket form,
// default upload path, optional custom domain, and "Done" button.
// Shows celebratory animation on completion.

import SwiftUI

struct OnboardingChooseBucketPanel: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confettiOffset: CGFloat = -200

    var body: some View {
        ZStack {
            // Main content
            mainContent

            // Celebration overlay
            if viewModel.showCelebration {
                celebrationOverlay
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Choose a Bucket")
                .font(.title)
                .fontWeight(.bold)

            Text("Select which R2 bucket to upload files to.")
                .font(.body)
                .foregroundColor(.secondary)

            // Bucket picker
            bucketPicker

            // Create new bucket toggle
            createBucketSection

            // Default path
            HStack {
                Text("Default path:")
                    .font(.subheadline)
                TextField("/", text: $viewModel.defaultPath)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            .padding(.horizontal, 60)

            // Custom domain (optional)
            HStack {
                Text("Custom domain:")
                    .font(.subheadline)
                TextField("cdn.example.com (optional)", text: $viewModel.customDomain)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            .padding(.horizontal, 60)

            Spacer()

            // Done button
            Button(action: {
                Task { await viewModel.finishSetup() }
            }) {
                Text("Done")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.selectedBucket.isEmpty)
        }
        .padding(32)
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
        .frame(maxWidth: 300)
    }

    // MARK: - Create Bucket

    private var createBucketSection: some View {
        VStack(spacing: 8) {
            if viewModel.showCreateBucket {
                HStack(spacing: 8) {
                    TextField("new-bucket-name", text: $viewModel.newBucketName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)

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
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else {
                Button("Create New Bucket") {
                    viewModel.showCreateBucket = true
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.subheadline)
            }
        }
    }

    // MARK: - Celebration

    private var celebrationOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow.gradient)
                .scaleEffect(reduceMotion ? 1.0 : 1.2)
                .animation(
                    reduceMotion ? .none :
                        .spring(response: 0.5, dampingFraction: 0.4),
                    value: viewModel.showCelebration
                )

            Text("You're all set!")
                .font(.title)
                .fontWeight(.bold)

            Text("R2Drop is ready to upload files.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
